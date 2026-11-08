#!/bin/bash
# ~/dotfiles/nvidia/nvidia-fan-curve.sh
#
# Curva de ventiladores para GPUs NVIDIA de escritorio bajo Hyprland/Wayland.
# Se instala como /usr/local/sbin/nvidia-fan-curve.sh y lo arranca Hyprland al
# iniciar sesión (ver hypr/.config/hypr/hyprland.lua), como root vía la regla
# NOPASSWD de /etc/sudoers.d/nvidia-fan-curve (la crea
# nvidia/install-nvidia-fan.sh). Detalles y reversión: docs/nvidia/fan-curve.md.
#
# Por qué root: GPUFanControlState y GPUTargetFanSpeed son escrituras
# privilegiadas de NV-CONTROL. Como usuario normal nvidia-settings las puede
# LEER pero no escribir -- y lo peor: no falla, ignora la escritura en
# silencio (rc=0), así que la única forma de saber si funcionó es leer el
# valor de vuelta.
#
# Por qué -c <display>: en Wayland no hay un Xorg de sesión; el display X es el
# Xwayland que levanta Hyprland (normalmente :1, pero el número puede variar).
# nvidia-settings habla NV-CONTROL a través de él. Si ese Xwayland exige
# cookie, root necesita `xhost +si:localuser:root` desde la sesión del usuario
# (o un XAUTHORITY legible).
#
# Uso:
#   sudo nvidia-fan-curve.sh             # loop de la curva (lo que usa Hyprland)
#   sudo nvidia-fan-curve.sh --once      # un solo ajuste (para probar)
#   nvidia-fan-curve.sh --status         # lee el estado actual (sin root)
#   sudo nvidia-fan-curve.sh --reset     # devuelve el control al firmware
#
# Variables de entorno:
#   NVIDIA_FAN_DISPLAY   display X a usar (default: autodetecta)
#   NVIDIA_FAN_INTERVAL  segundos entre ajustes (default: 5)
#   NVIDIA_FAN_GPU       índice de GPU (default: 0)
#   NVIDIA_FAN_FORCE     =1 para ignorar el chequeo de chasis portátil

set -u

SELF=${0##*/}
GPU=${NVIDIA_FAN_GPU:-0}
INTERVAL=${NVIDIA_FAN_INTERVAL:-5}

# Tabla de la curva: temperatura máxima (<=) en °C -> porcentaje del fan.
THRESHOLDS=(49 59 69 77 84 200)
SPEEDS=(30 42 55 70 85 100)
# Cuántos grados tiene que caer la temperatura para BAJAR un escalón (evita
# que el fan oscile arriba/abajo cuando la temp queda justo en un umbral).
HYSTERESIS=3

die() { printf '%s: %s\n' "$SELF" "$1" >&2; exit 1; }
say() { printf '%s: %s\n' "$SELF" "$1"; }

# ---------------------------------------------------------------------------
# Display X: autodetección
# ---------------------------------------------------------------------------
# Si corre como root, el XAUTHORITY del usuario que invocó sudo no se hereda.
# Si existe, se usa; si no (el Xwayland de Hyprland arranca sin -auth en muchas
# versiones), alcanza con que el servidor no exija cookie.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ -z "${XAUTHORITY:-}" ]; then
    sudo_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    if [ -n "$sudo_home" ] && [ -r "$sudo_home/.Xauthority" ]; then
        export XAUTHORITY="$sudo_home/.Xauthority"
    fi
fi

display_candidates() {
    local d pid
    for d in "${NVIDIA_FAN_DISPLAY:-}" "${DISPLAY:-}" "${WAYLAND_DISPLAY:-}"; do
        [ -n "$d" ] && printf '%s\n' "$d"
    done
    # Xwayland lleva el display como primer argumento: "Xwayland :1 -rootless ..."
    for pid in $(pgrep -x Xwayland 2>/dev/null); do
        tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -m1 -oE '^:[0-9]+$'
    done
    # Por si el proceso todavía no aparece en pgrep (arranque temprano).
    ls /tmp/.X11-unix 2>/dev/null | grep -oE '^X[0-9]+$' | sed 's/^X/:/'
}

# Primer display donde nvidia-settings puede LEER NV-CONTROL.
detect_display_read() {
    local d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        if nvidia-settings -c "$d" -q fans >/dev/null 2>&1; then
            printf '%s' "$d"
            return 0
        fi
    done < <(display_candidates | awk '!seen[$0]++')
    return 1
}

# Primer display donde nvidia-settings puede ESCRIBIR de verdad. Ojo: como
# usuario las escrituras fallan en silencio, así que se verifica leyendo de
# vuelta GPUFanControlState (tiene que quedar en 1).
detect_display_rw() {
    local d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        # Primero la velocidad (con el control apagado no hace nada) y recién
        # después se habilita el control: si la velocidad no se pudiera
        # escribir, el firmware sigue mandando en vez de quedar a 0 %.
        nvidia-settings -c "$d" -a "[fan:0]/GPUTargetFanSpeed=50" >/dev/null 2>&1
        nvidia-settings -c "$d" -a "[gpu:$GPU]/GPUFanControlState=1" >/dev/null 2>&1
        if [ "$(control_state "$d")" = "1" ]; then
            printf '%s' "$d"
            return 0
        fi
    done < <(display_candidates | awk '!seen[$0]++')
    return 1
}

# ---------------------------------------------------------------------------
# nvidia-settings helpers
# ---------------------------------------------------------------------------
# Formato de salida: "  Attribute 'GPUFanControlState' (arch-pc:1[gpu:0]): 0."
attr_value() { # $1=display $2=atributo
    nvidia-settings -c "$1" -q "$2" 2>/dev/null \
        | sed -n 's/.*):[[:space:]]*\([0-9][0-9]*\)\..*/\1/p' | head -1
}

control_state() { attr_value "$1" "[gpu:$GPU]/GPUFanControlState"; }

fan_count() {
    local n
    n="$(nvidia-settings -c "$DISP" -q fans 2>/dev/null | grep -c '\[fan:')"
    [ "$n" -gt 0 ] || n=1
    printf '%s' "$n"
}

set_fan() {
    local speed="$1" i args
    args=(-c "$DISP" -a "[gpu:$GPU]/GPUFanControlState=1")
    for ((i = 0; i < FANS; i++)); do
        args+=(-a "[fan:$i]/GPUTargetFanSpeed=$speed")
    done
    nvidia-settings "${args[@]}" >/dev/null 2>&1
}

restore_auto() {
    [ -n "${DISP:-}" ] || return 0
    nvidia-settings -c "$DISP" -a "[gpu:$GPU]/GPUFanControlState=0" >/dev/null 2>&1 || true
}

target_for() {
    local t="$1" i
    for i in "${!THRESHOLDS[@]}"; do
        if [ "$t" -le "${THRESHOLDS[$i]}" ]; then
            printf '%s' "${SPEEDS[$i]}"
            return 0
        fi
    done
    printf '%s' "${SPEEDS[${#SPEEDS[@]} - 1]}"
}

gpu_temp() {
    nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits -i "$GPU" 2>/dev/null | tr -d ' '
}

no_display_error() {
    die "no encontré un display donde nvidia-settings pueda escribir el fan.
  - ¿Hyprland/Xwayland está corriendo?
  - Probá un display puntual: NVIDIA_FAN_DISPLAY=:1 $SELF ${1:-}
  - Si este Xwayland exige cookie: 'xhost +si:localuser:root' en la sesión."
}

# ---------------------------------------------------------------------------
# Modos
# ---------------------------------------------------------------------------
status() {
    local disp temp
    disp="$(detect_display_read)" || die "no encontré un display X con NV-CONTROL (¿Hyprland/Xwayland corriendo?)"
    temp="$(gpu_temp)"
    printf 'display=%s gpu=%s temp=%s°C control=%s fan0=%s%%\n' \
        "$disp" "$GPU" "${temp:-?}" "$(control_state "$disp")" \
        "$(attr_value "$disp" "[fan:0]/GPUTargetFanSpeed")"
}

once() {
    local temp target
    temp="$(gpu_temp)"
    [ -n "$temp" ] || die "nvidia-smi no devolvió temperatura para la GPU $GPU"
    target="$(target_for "$temp")"
    set_fan "$target"
    [ "$(control_state "$DISP")" = "1" ] || no_display_error "--once"
    say "temp=${temp}°C -> fan=${target}%"
}

loop() {
    local temp last="" target
    trap restore_auto EXIT INT TERM
    # Espera a que Xwayland/NV-CONTROL estén disponibles: en el arranque de
    # Hyprland este script puede ganarle la carrera al servidor X.
    until DISP="$(detect_display_rw)"; do
        sleep 2
    done
    FANS="$(fan_count)"
    say "curva activa: display=$DISP gpu=$GPU fans=$FANS intervalo=${INTERVAL}s (Ctrl+C vuelve a auto)"

    while :; do
        temp="$(gpu_temp)"
        if [ -n "$temp" ]; then
            target="$(target_for "$temp")"
            # Al bajar de escalón se pide un poco más de margen (histéresis).
            if [ -n "$last" ] && [ "$target" -lt "$last" ]; then
                target="$(target_for "$((temp + HYSTERESIS))")"
            fi
            if [ "$target" != "$last" ]; then
                set_fan "$target"
                last="$target"
                say "temp=${temp}°C -> fan=${target}%"
            fi
        fi
        sleep "$INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
case "${1:-}" in
    --status)
        status
        exit 0
        ;;
    --reset)
        [ "$(id -u)" -eq 0 ] || die "--reset necesita root (sudo)"
        DISP="$(detect_display_read)" || die "no encontré un display X con NV-CONTROL"
        restore_auto
        say "control del fan devuelto al firmware (GPUFanControlState=0)"
        exit 0
        ;;
    --once)
        [ "$(id -u)" -eq 0 ] || die "escribir el fan necesita root (sudo)"
        ;;
    "" | --loop)
        [ "$(id -u)" -eq 0 ] || die "escribir el fan necesita root (sudo)"
        ;;
    -h | --help)
        sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        die "opción desconocida: $1 (ver --help)"
        ;;
esac

# En laptops el fan del dGPU lo controla el EC del fabricante, no nvidia-settings
# (escribirlo no hace nada o pelea con la curva del EC). chassis_type 8/9/10/14
# = portable/laptop/notebook/subnotebook.
chassis="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo 0)"
case "$chassis" in
    8 | 9 | 10 | 14)
        if [ "${NVIDIA_FAN_FORCE:-0}" != "1" ]; then
            say "chasis portátil (chassis_type=$chassis): el fan lo maneja el EC, no nvidia-settings."
            say "Se omite la curva. Para intentarlo igual: NVIDIA_FAN_FORCE=1 $SELF"
            exit 0
        fi
        ;;
esac

if [ "${1:-}" = "--once" ]; then
    DISP="$(detect_display_rw)" || no_display_error "--once"
    FANS="$(fan_count)"
    trap restore_auto EXIT INT TERM
    once
    exit 0
fi

loop
