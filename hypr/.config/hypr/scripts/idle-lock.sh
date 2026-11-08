#!/bin/bash
# ~/.config/hypr/scripts/idle-lock.sh — bloqueo automático configurable
#
# Controla hypridle desde Waybar (módulo custom/idle) y atajos:
#   idle-lock.sh apply     genera la config y (re)arranca hypridle (autostart)
#   idle-lock.sh toggle    activa/desactiva el bloqueo automático  (click / SUPER+SHIFT+L)
#   idle-lock.sh set N     bloquea tras N minutos sin uso; N=0 desactiva
#   idle-lock.sh menu      elige los minutos en Walker            (click derecho / SUPER+CTRL+L)
#   idle-lock.sh status    JSON para Waybar
#
# Desactivado = modo "cafeína": hypridle no corre, así que no se atenúa,
# no se bloquea, no se apaga la pantalla ni se suspende por inactividad.
# El estado persiste entre reinicios en $XDG_STATE_HOME/idle-lock/.
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/idle-lock"
MINUTES_FILE="$STATE_DIR/minutes"
ENABLED_FILE="$STATE_DIR/enabled"
CONF="$STATE_DIR/hypridle.conf"
DEFAULT_MINUTES=5
WAYBAR_SIGNAL=9 # debe coincidir con "signal" de custom/idle en waybar/config.jsonc

mkdir -p "$STATE_DIR"

minutes() {
    local m
    m="$(cat "$MINUTES_FILE" 2>/dev/null || true)"
    [[ "$m" =~ ^[1-9][0-9]*$ ]] && echo "$m" || echo "$DEFAULT_MINUTES"
}

enabled() {
    [ "$(cat "$ENABLED_FILE" 2>/dev/null || echo 1)" != "0" ]
}

write_conf() {
    local lock=$(($(minutes) * 60))
    local dim_before=$((lock / 2 < 150 ? lock / 2 : 150))
    local dim=$((lock - dim_before))
    local screen_off=$((lock + 30))
    local suspend=$((lock + 900 > 1200 ? lock + 900 : 1200))

    cat >"$CONF" <<EOF
# Generado por ~/.config/hypr/scripts/idle-lock.sh — no editar a mano
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
}

# Atenúa el brillo antes de bloquear
listener {
    timeout = $dim
    on-timeout = brightnessctl -s set 10
    on-resume = brightnessctl -r
}

# Apaga el teclado retroiluminado (si aplica en el Legion)
listener {
    timeout = $dim
    on-timeout = brightnessctl -sd rgb:kbd_backlight set 0
    on-resume = brightnessctl -rd rgb:kbd_backlight
}

# Bloquea la sesión
listener {
    timeout = $lock
    on-timeout = loginctl lock-session
}

# Apaga la pantalla
listener {
    timeout = $screen_off
    on-timeout = hyprctl dispatch 'hl.dsp.dpms({action = "off"})'
    on-resume = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
}

# Suspende la laptop
listener {
    timeout = $suspend
    on-timeout = systemctl suspend
}
EOF
}

refresh_waybar() {
    pkill -RTMIN+"$WAYBAR_SIGNAL" -x waybar 2>/dev/null || true
}

apply() {
    pkill -x hypridle 2>/dev/null || true
    # esperar a que muera para no tener dos instancias
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x hypridle >/dev/null || break; sleep 0.1; done
    if enabled; then
        write_conf
        setsid -f hypridle -q -c "$CONF" >/dev/null 2>&1
    fi
    refresh_waybar
}

notify() {
    notify-send -t 2500 -a "Bloqueo automático" "Bloqueo automático" "$1" 2>/dev/null || true
}

set_minutes() {
    local n="$1"
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        notify "Valor inválido: '$n' (usa minutos, 0 para desactivar)"
        exit 1
    fi
    n=$((10#$n))
    if [ "$n" -eq 0 ]; then
        echo 0 >"$ENABLED_FILE"
        apply
        notify "Desactivado — la pantalla no se bloqueará"
    else
        echo "$n" >"$MINUTES_FILE"
        echo 1 >"$ENABLED_FILE"
        apply
        notify "Se bloqueará tras $n min sin uso"
    fi
}

toggle() {
    if enabled; then set_minutes 0; else set_minutes "$(minutes)"; fi
}

menu() {
    local current choice n
    if enabled; then current="Bloquear tras $(minutes) min"; else current="Desactivado"; fi
    choice="$(printf '%s\n' \
        "Desactivado" \
        "Bloquear tras 1 min" \
        "Bloquear tras 5 min" \
        "Bloquear tras 10 min" \
        "Bloquear tras 15 min" \
        "Bloquear tras 30 min" \
        "Bloquear tras 60 min" \
        "Otro tiempo…" |
        walker --dmenu -p "Bloqueo automático (ahora: $current)" 2>/dev/null || true)"

    case "$choice" in
    "") exit 0 ;;
    "Desactivado") set_minutes 0 ;;
    "Otro tiempo…")
        n="$(walker --dmenu --inputonly -p "Minutos sin uso antes de bloquear (0 = desactivar)" 2>/dev/null || true)"
        [ -n "$n" ] && set_minutes "$n"
        ;;
    *)
        n="${choice//[^0-9]/}"
        [ -n "$n" ] && set_minutes "$n"
        ;;
    esac
}

status() {
    #  = nf-fa-lock,  = nf-fa-coffee
    if enabled; then
        printf '{"text":"\\uf023 %sm","class":"on","tooltip":"Bloqueo automático tras %s min sin uso\\nClick: desactivar · Click derecho: cambiar tiempo"}\n' "$(minutes)" "$(minutes)"
    else
        printf '{"text":"\\uf0f4","class":"off","tooltip":"Bloqueo automático DESACTIVADO\\nClick: activar (%s min) · Click derecho: cambiar tiempo"}\n' "$(minutes)"
    fi
}

case "${1:-}" in
apply) apply ;;
toggle) toggle ;;
set) set_minutes "${2:-}" ;;
menu) menu ;;
status) status ;;
*)
    echo "uso: $(basename "$0") apply|toggle|set N|menu|status" >&2
    exit 2
    ;;
esac
