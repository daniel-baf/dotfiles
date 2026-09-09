#!/bin/bash
# ~/.config/hypr/scripts/toggle-display-mode.sh — SUPER+SHIFT+P
# Atajo rápido tipo "Windows+P": alterna entre extender (cada pantalla en su
# posición) y duplicar (todas hacen mirror de la principal). Para acomodar
# posiciones o resoluciones a mano, usá la GUI: nwg-displays (SUPER+P).
set -e

STATE_FILE="/tmp/hypr-display-mode-$UID"

mapfile -t monitors < <(hyprctl monitors -j | jq -r '.[].name')

if [ "${#monitors[@]}" -lt 2 ]; then
    notify-send "Pantallas" "Solo hay una pantalla conectada." 2>/dev/null || true
    exit 0
fi

primary="${monitors[0]}"
mode="extend"
[ -f "$STATE_FILE" ] && mode="$(cat "$STATE_FILE")"

if [ "$mode" = "extend" ]; then
    for m in "${monitors[@]:1}"; do
        hyprctl keyword monitor "$m,preferred,auto,1,mirror,$primary"
    done
    echo "mirror" > "$STATE_FILE"
    notify-send "Pantallas" "Modo: duplicar (mirror)" 2>/dev/null || true
else
    x=0
    for m in "${monitors[@]}"; do
        hyprctl keyword monitor "$m,preferred,${x}x0,1"
        x=$((x + 1920))
    done
    echo "extend" > "$STATE_FILE"
    notify-send "Pantallas" "Modo: extender" 2>/dev/null || true
fi
