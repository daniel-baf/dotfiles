#!/bin/bash
# ~/.config/ranger/scope.sh — gestionado desde ~/dotfiles (Stow)
# Preview para ranger: markdown con formato real (glow), diagramas
# (Mermaid/Graphviz/PlantUML) renderizados a imagen, e imágenes/PDF/SVG
# mostrados directo en la terminal vía el protocolo de imágenes de kitty
# (kitty es la terminal de este setup -- ver kitty/ en dotfiles).
#
# Códigos de salida que entiende ranger:
#   0 = stdout es el preview de texto        1 = sin preview
#   2 = mostrar el archivo tal cual (texto)  6 = mostrar imagen en $IMAGE_CACHE_PATH
#   7 = mostrar el archivo mismo como imagen

FILE_PATH="$1"
PV_WIDTH="$2"
# shellcheck disable=SC2034
PV_HEIGHT="$3"
IMAGE_CACHE_PATH="$4"
PV_IMAGE_ENABLED="$5"

FILE_EXTENSION="${FILE_PATH##*.}"
FILE_EXTENSION_LOWER=$(printf '%s' "$FILE_EXTENSION" | tr '[:upper:]' '[:lower:]')

case "$FILE_EXTENSION_LOWER" in
    md|markdown)
        if command -v glow >/dev/null 2>&1; then
            glow -s dark -w "$PV_WIDTH" -- "$FILE_PATH" && exit 0
        fi
        exit 1
        ;;
    mmd|mermaid)
        [ "$PV_IMAGE_ENABLED" = "True" ] || exit 1
        command -v mmdc >/dev/null 2>&1 || exit 1
        tmp_png="$(mktemp --suffix=.png)"
        if mmdc -i "$FILE_PATH" -o "$tmp_png" -b transparent >/dev/null 2>&1; then
            mv "$tmp_png" "$IMAGE_CACHE_PATH" && exit 6
        fi
        rm -f "$tmp_png"
        exit 1
        ;;
    dot|gv)
        [ "$PV_IMAGE_ENABLED" = "True" ] || exit 1
        command -v dot >/dev/null 2>&1 || exit 1
        dot -Tpng "$FILE_PATH" -o "$IMAGE_CACHE_PATH" && exit 6
        exit 1
        ;;
    puml|plantuml)
        [ "$PV_IMAGE_ENABLED" = "True" ] || exit 1
        command -v plantuml >/dev/null 2>&1 || exit 1
        plantuml -tpng -pipe < "$FILE_PATH" > "$IMAGE_CACHE_PATH" && exit 6
        exit 1
        ;;
esac

MIMETYPE=$(file --mime-type -Lb "$FILE_PATH")
case "$MIMETYPE" in
    image/svg+xml)
        [ "$PV_IMAGE_ENABLED" = "True" ] || exit 1
        if command -v rsvg-convert >/dev/null 2>&1; then
            rsvg-convert "$FILE_PATH" -o "$IMAGE_CACHE_PATH" && exit 6
        elif command -v convert >/dev/null 2>&1; then
            convert -background none "$FILE_PATH" "$IMAGE_CACHE_PATH" && exit 6
        fi
        exit 1
        ;;
    image/*)
        [ "$PV_IMAGE_ENABLED" = "True" ] && exit 7
        exit 1
        ;;
    application/pdf)
        [ "$PV_IMAGE_ENABLED" = "True" ] || exit 1
        command -v pdftoppm >/dev/null 2>&1 || exit 1
        tmp_prefix="$(mktemp -u)"
        if pdftoppm -f 1 -l 1 -scale-to-x 1200 -scale-to-y -1 -singlefile -png \
            "$FILE_PATH" "$tmp_prefix" 2>/dev/null; then
            mv "${tmp_prefix}.png" "$IMAGE_CACHE_PATH" && exit 6
        fi
        exit 1
        ;;
    text/* | application/json | application/xml | application/x-yaml)
        if command -v bat >/dev/null 2>&1; then
            bat --color=always --style=plain --paging=never -- "$FILE_PATH" && exit 0
        fi
        exit 2
        ;;
esac

exit 1
