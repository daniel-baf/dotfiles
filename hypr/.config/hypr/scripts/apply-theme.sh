#!/bin/bash
# ~/.config/hypr/scripts/apply-theme.sh — gestionado desde ~/dotfiles (Stow)
#
# Idempotente: lee el modo actual (gsettings org.gnome.desktop.interface
# color-scheme -- ÚNICA fuente de verdad, no hay archivo de estado aparte) y
# reaplica esa paleta a todo lo que no la retoma solo. Lo llaman:
#   - toggle-theme.sh, después de invertir el valor en gsettings.
#   - hyprland.lua en cada arranque de Hyprland (los bordes/sombra que
#     hyprctl keyword cambia en caliente no persisten solos entre sesiones).
#
# Nota sobre el fix real de Chrome/páginas web con "prefers-color-scheme:
# system": gsettings ya tenía color-scheme correcto, pero sin
# ~/.config/gtk-{3,4}.0/settings.ini no había forma de que Chrome (toolkit
# GTK3) se enterara -- sin xsettings daemon en Hyprland, GtkSettings nunca
# leía la propiedad "gtk-application-prefer-dark-theme". Este script la
# escribe cada vez, así queda sincronizada con el toggle del rice.
set -e

scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
if [ "$scheme" = "prefer-light" ]; then
    mode="light"
    prefer_dark=0
    border_active_1="rgba(2e7de9ee)"
    border_active_2="rgba(9854f1ee)"
    border_inactive="rgba(c4c8daaa)"
    shadow_color="0xeee1e2e7"
else
    mode="dark"
    prefer_dark=1
    border_active_1="rgba(7aa2f7ee)"
    border_active_2="rgba(bb9af7ee)"
    border_inactive="rgba(292e42aa)"
    shadow_color="0xee1a1b26"
fi

# 1. Paleta compartida (waybar/swaync/wlogout/walker vía @import GTK CSS)
ln -sf "$HOME/.config/theme/$mode.css" "$HOME/.config/theme/current.css"

# 2. Kitty (aplica a ventanas nuevas; las abiertas se quedan con el tema con
#    el que arrancaron -- no hay listen_on compartido para remote-control)
ln -sf "$HOME/.config/kitty/theme/$mode.conf" "$HOME/.config/kitty/theme/current.conf"

# 3. GTK settings.ini -- lo que realmente arregla prefers-color-scheme en
#    Chrome y cualquier app GTK3/4. Machine-local, fuera del repo (mismo
#    criterio que ~/.gitconfig.local).
for ver in 3.0 4.0; do
    dir="$HOME/.config/gtk-$ver"
    mkdir -p "$dir"
    cat > "$dir/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=$prefer_dark
gtk-theme-name=Adwaita
EOF
done

# 4. Bordes/sombra de Hyprland en caliente. hyprland.lua usa el config Lua
#    nativo de Hyprland (non-legacy parser) -- "hyprctl keyword" no aplica
#    ahí ("keyword can't work with non-legacy parsers. Use eval."), así que
#    se reaplica el mismo hl.config({...}) que arma hyprland.lua vía
#    "hyprctl eval".
hyprctl eval "hl.config({ general = { col = { active_border = { colors = {\"$border_active_1\", \"$border_active_2\"}, angle = 45 }, inactive_border = \"$border_inactive\" } }, decoration = { shadow = { color = $shadow_color } } })" >/dev/null 2>&1 || true

# 5. Reload de cada app
swaync-client --reload-css >/dev/null 2>&1 || true
(pkill waybar || true; sleep 0.2; setsid waybar >/dev/null 2>&1 &) &
disown
(pkill -f 'walker --gapplication-service' || true; sleep 0.2; setsid walker --gapplication-service >/dev/null 2>&1 &) &
disown

notify-send "Tema" "Modo: $mode" 2>/dev/null || true
