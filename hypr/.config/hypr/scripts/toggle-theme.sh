#!/bin/bash
# ~/.config/hypr/scripts/toggle-theme.sh — click en el módulo custom/theme-toggle de waybar
# Invierte gsettings org.gnome.desktop.interface color-scheme (fuente de
# verdad única) y delega el resto en apply-theme.sh.
set -e

scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
if [ "$scheme" = "prefer-light" ]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
else
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
fi

"$(dirname "$0")/apply-theme.sh"
