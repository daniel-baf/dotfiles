#!/bin/bash
# Estado del módulo custom/theme-toggle de Waybar. Fuente de verdad única:
# gsettings org.gnome.desktop.interface color-scheme -- ver
# ~/.config/hypr/scripts/apply-theme.sh, que es quien la cambia.
#
# Íconos con \uXXXX (nf-fa-moon-o / nf-fa-sun-o): escritos como el glyph
# literal se pierden en algunos editores/pipes -- con el escape and\u no hay
# ambigüedad de bytes.
scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)

if [ "$scheme" = "'prefer-light'" ]; then
    printf '{"text":"","tooltip":"Tema: claro (click para pasar a oscuro)"}\n'
else
    printf '{"text":"","tooltip":"Tema: oscuro (click para pasar a claro)"}\n'
fi
