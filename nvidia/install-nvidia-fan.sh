#!/bin/bash
# ~/dotfiles/nvidia/install-nvidia-fan.sh
#
# Instala la curva de ventiladores de la GPU NVIDIA (ver
# nvidia/nvidia-fan-curve.sh y docs/nvidia/fan-curve.md). Todo idempotente: se
# puede correr las veces que sea.
#
# Qué hace:
#   1. Verifica que haya una GPU NVIDIA con el driver propietario (nvidia-smi).
#   2. Instala nvidia-settings si falta (solo en la rama nvidia-utils; en los
#      drivers legacy el paquete de settings es otro y se avisa).
#   3. Copia el script a /usr/local/sbin/nvidia-fan-curve.sh (root:root 755).
#   4. Crea /etc/sudoers.d/nvidia-fan-curve para que tu usuario pueda correr
#      SOLO ese script como root sin contraseña (lo necesita para escribir
#      GPUFanControlState). El script es de root y no lo podés editar, así que
#      la regla no da root arbitrario.
#   5. Prueba un ajuste y explica cómo arrancarlo/verificarlo/revertirlo.
#
# El autostart en Hyprland ya está en hypr/.config/hypr/hyprland.lua (vía
# Stow): si el script no está instalado, el arranque no hace nada.

set -u

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$DOTFILES_DIR/nvidia"
TARGET=/usr/local/sbin/nvidia-fan-curve.sh
SUDOERS=/etc/sudoers.d/nvidia-fan-curve

step() { printf '==> %s\n' "$1"; }
warn() { printf '    %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. GPU NVIDIA
# ---------------------------------------------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L 2>/dev/null | grep -q '^GPU'; then
    warn "No detecté una GPU NVIDIA con el driver propietario (nvidia-smi)."
    warn "Instalá el driver (nvidia-utils o el paquete legacy que corresponda) y volvé a correr esto."
    exit 0
fi

step "GPU detectada: $(nvidia-smi -L | head -1)"

# ---------------------------------------------------------------------------
# 2. nvidia-settings
# ---------------------------------------------------------------------------
if ! command -v nvidia-settings >/dev/null 2>&1; then
    if pacman -Qq 2>/dev/null | grep -qx 'nvidia-utils'; then
        step "Instalando nvidia-settings..."
        if ! sudo pacman -S --needed --noconfirm nvidia-settings; then
            warn "No se pudo instalar nvidia-settings. Instalalo a mano: sudo pacman -S nvidia-settings"
            exit 1
        fi
    else
        warn "Falta nvidia-settings y tu driver no es 'nvidia-utils' (¿rama legacy?)."
        warn "Instalá el paquete de settings que corresponda a tu driver (p.ej. nvidia-580xx-settings)"
        warn "y volvé a correr este script."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 3. Script
# ---------------------------------------------------------------------------
step "Instalando $TARGET..."
sudo install -Dm755 "$SRC_DIR/nvidia-fan-curve.sh" "$TARGET"

# ---------------------------------------------------------------------------
# 4. sudoers (NOPASSWD solo para ese script)
# ---------------------------------------------------------------------------
INVOKER="${SUDO_USER:-$(id -un)}"
step "Permitiendo a '$INVOKER' correr la curva sin contraseña ($SUDOERS)..."
tmp="$(mktemp)"
printf '%s ALL=(root) NOPASSWD: %s\n' "$INVOKER" "$TARGET" > "$tmp"
sudo install -Dm440 -o root -g root "$tmp" "$SUDOERS"
rm -f "$tmp"
if ! sudo visudo -cf "$SUDOERS" >/dev/null 2>&1; then
    warn "La regla de sudoers no valida; la borro para no romper sudo."
    sudo rm -f "$SUDOERS"
    exit 1
fi

# ---------------------------------------------------------------------------
# 5. Prueba
# ---------------------------------------------------------------------------
step "Probando un ajuste (no deja la curva corriendo)..."
if sudo -n "$TARGET" --once; then
    step "OK: se pudo escribir el fan."
else
    warn "Falló el ajuste. Revisá:"
    warn "  nvidia-settings -q fans                      # ¿hay fans?"
    warn "  $TARGET --status                             # display/temp/estado"
    warn "En algunos setups Xwayland exige cookie: probá 'xhost +si:localuser:root'"
    warn "en la sesión (y volvé a correr este script)."
fi
sudo -n "$TARGET" --reset >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
step "Listo. Hyprland arranca la curva en el próximo login."
echo "    Arrancar ahora:  sudo $TARGET &"
echo "    Ver estado:      $TARGET --status"
echo "    Volver a auto:   sudo $TARGET --reset"
echo "    Detalles:        $DOTFILES_DIR/docs/nvidia/fan-curve.md"
