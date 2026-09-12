#!/bin/bash
# ~/.config/hypr/scripts/toggle-display-mode.sh — SUPER+SHIFT+P
# Atajo rápido tipo "Windows+P": alterna entre extender (el layout guardado en
# monitors.lua por nwg-displays) y duplicar (todas hacen mirror de la
# principal). Para acomodar posiciones o resoluciones a mano, usá la GUI:
# nwg-displays (SUPER+P).
set -e

STATE_FILE="/tmp/hypr-display-mode-$UID"

# 'monitors all' y no 'monitors': los outputs en mirror no aparecen en el
# listado normal, y sin esto el toggle quedaba trabado en modo duplicar
# (veía una sola pantalla y salía). Se filtran los desactivados.
mapfile -t monitors < <(hyprctl monitors all -j | jq -r '.[] | select(.disabled == false) | .name')

if [ "${#monitors[@]}" -lt 2 ]; then
    notify-send "Pantallas" "Solo hay una pantalla conectada." 2>/dev/null || true
    exit 0
fi

primary="${monitors[0]}"
mode="extend"
[ -f "$STATE_FILE" ] && mode="$(cat "$STATE_FILE")"

if [ "$mode" = "extend" ]; then
    # 'hyprctl keyword' no sirve con config lua (Hyprland 0.55+): responde
    # "keyword can't work with non-legacy parsers. Use eval." Se usa eval con
    # el mismo hl.monitor del config.
    for m in "${monitors[@]:1}"; do
        hyprctl eval "hl.monitor({ output = \"$m\", mode = \"preferred\", position = \"auto\", scale = 1, mirror = \"$primary\" })" >/dev/null
    done
    echo "mirror" > "$STATE_FILE"
    notify-send "Pantallas" "Modo: duplicar (mirror)" 2>/dev/null || true
else
    # Volver a extender = reaplicar la config: 'hyprctl reload' recarga el
    # layout guardado en monitors.lua (las posiciones viven ahí, no acá --
    # antes este script recolocaba las pantallas a mano con anchos hardcodeados
    # de 1920 px, que ignoraban el scale del eDP).
    hyprctl reload
    echo "extend" > "$STATE_FILE"
    notify-send "Pantallas" "Modo: extender" 2>/dev/null || true
fi
