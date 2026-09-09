#!/bin/bash
# Estado de Num Lock para el módulo custom/numlock de Waybar.
# Lee el LED real en /sys/class/leds en vez de "contar" toggles -- así no se
# puede desincronizar si se presiona la tecla dos veces seguidas rápido.
led=$(find /sys/class/leds -maxdepth 1 -iname '*numlock*' -print -quit)

state="0"
if [ -n "$led" ]; then
    state=$(cat "$led/brightness" 2>/dev/null || echo 0)
fi

if [ "$state" != "0" ]; then
    printf '{"text":"","class":"on","tooltip":"Num Lock: ON"}\n'
else
    printf '{"text":"","class":"off","tooltip":"Num Lock: OFF"}\n'
fi
