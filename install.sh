#!/bin/bash
# ~/dotfiles/install.sh
#
# Setup completo para una PC nueva con Arch + Hyprland (ver docs/hyprland/instalacion.md).
# Instala paquetes, aplica los symlinks con GNU Stow, y configura git + SSH
# de forma interactiva (nunca se hardcodean credenciales en este repo).
#
# Uso: ./install.sh [--skip-backup]
#   --skip-backup   no crea el snapshot btrfs de /home (paso 0). El backup
#                    de archivos que chocan con Stow (paso 6) siempre se hace,
#                    es instantáneo y necesario para que Stow no falle.

set -e

SKIP_BACKUP=false
for arg in "$@"; do
    case "$arg" in
        --skip-backup) SKIP_BACKUP=true ;;
        *) echo "Uso: ./install.sh [--skip-backup]  |  Usage: ./install.sh [--skip-backup]"; exit 1 ;;
    esac
done

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOW_PACKAGES="git kitty hypr ranger waybar walker swaync wlogout elephant bash claude caveman chrome spotify theme"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# Idioma / Language
# ---------------------------------------------------------------------------
echo "Idioma / Language:"
echo "  1) Español (default)"
echo "  2) English"
read -rp "[1/2]: " lang_choice
case "$lang_choice" in
    2) LOCALE="en" ;;
    *) LOCALE="es" ;;
esac

# Layout de teclado por defecto para Hyprland (ver hyprland.lua): en inglés
# arranca en "us", en español en "latam". Se guarda fuera del repo porque
# hyprland.lua está gestionado con Stow -- no queremos que install.sh deje
# el repo "sucio" en cada corrida.
mkdir -p "$HOME/.config/hypr"
if [ "$LOCALE" = "en" ]; then
    echo "us,latam" > "$HOME/.config/hypr/.kb_layout"
else
    echo "latam,us" > "$HOME/.config/hypr/.kb_layout"
fi

# say "<es>" "<en>"            -> imprime el mensaje con salto de línea
# ask "<es prompt>" "<en prompt>" -> lo mismo pero sin salto, para read -rp "$(ask ...)"
say() {
    if [ "$LOCALE" = "en" ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi
}
ask() {
    if [ "$LOCALE" = "en" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}
# ask_yn "<es prompt>" "<en prompt>" -> true/false (default No)
ask_yn() {
    local ans
    read -rp "$(ask "$1" "$2")" ans
    [[ "$ans" =~ ^[sSyY] ]]
}

ensure_nvm_node() {
    # Instala Node vía nvm (dentro de $HOME, sin sudo) la primera vez que se
    # necesita, y lo deja disponible para el resto de esta corrida del
    # script. pacman instala nodejs/npm en /usr (root), lo que rompe
    # "npm install -g" sin sudo -- por eso Node se maneja acá con nvm.
    local NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        say "==> Instalando nvm (Node en \$HOME, para que 'npm install -g' no necesite sudo)..." \
            "==> Installing nvm (Node under \$HOME, so 'npm install -g' doesn't need sudo)..."
        local nvm_latest
        nvm_latest="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
            | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_latest:-v0.40.1}/install.sh" | bash
    fi
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    nvm install --lts >/dev/null
}

say "==> Dotfiles en: $DOTFILES_DIR" "==> Dotfiles at: $DOTFILES_DIR"

# ---------------------------------------------------------------------------
# 0. Backup de seguridad antes de tocar nada en $HOME (opcional: --skip-backup)
# ---------------------------------------------------------------------------
# Tu / (y @home) son btrfs con subvolúmenes (ver docs/hyprland/instalacion.md,
# paso 3) -> si detectamos btrfs, además del backup de archivos de abajo,
# sacamos un snapshot de solo lectura de /home completo como red de seguridad.
if $SKIP_BACKUP; then
    say "==> --skip-backup: se omite el snapshot btrfs de \$HOME." \
        "==> --skip-backup: skipping the btrfs snapshot of \$HOME."
elif [ "$(stat -f --format=%T "$HOME" 2>/dev/null)" = "btrfs" ] && command -v btrfs >/dev/null 2>&1; then
    say "==> \$HOME es btrfs." "==> \$HOME is btrfs."
    if [ -d /.snapshots ]; then
        snap_name="home-preinstall-$(date +%Y%m%d-%H%M%S)"
        say "==> Creando snapshot de solo lectura: /.snapshots/$snap_name" \
            "==> Creating read-only snapshot: /.snapshots/$snap_name"
        if sudo btrfs subvolume snapshot -r /home "/.snapshots/$snap_name"; then
            say "==> Snapshot listo. Para volver atrás si algo sale mal:" \
                "==> Snapshot ready. To roll back if something goes wrong:"
            echo "    sudo btrfs subvolume snapshot /.snapshots/$snap_name /home_restaurado"
        else
            say "==> No se pudo crear el snapshot btrfs, seguimos solo con el backup de archivos." \
                "==> Could not create the btrfs snapshot, continuing with just the file backup."
        fi
    else
        say "==> No encontré /.snapshots montado, seguimos solo con el backup de archivos." \
            "==> Could not find /.snapshots mounted, continuing with just the file backup."
    fi
else
    say "==> \$HOME no es btrfs (o falta el binario 'btrfs'): solo se hace el backup de archivos." \
        "==> \$HOME is not btrfs (or the 'btrfs' binary is missing): only the file backup is done."
fi

# ---------------------------------------------------------------------------
# 1. git
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    say "==> Instalando git..." "==> Installing git..."
    sudo pacman -S --needed --noconfirm git
else
    say "==> git ya está instalado ($(git --version))." "==> git is already installed ($(git --version))."
fi

# ---------------------------------------------------------------------------
# 2. paru (necesario para walker, wlogout y varias apps opcionales, solo AUR)
# ---------------------------------------------------------------------------
if ! command -v paru >/dev/null 2>&1; then
    say "==> Instalando paru..." "==> Installing paru..."
    sudo pacman -S --needed --noconfirm base-devel
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
    (cd "$tmpdir/paru" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
else
    say "==> paru ya está instalado." "==> paru is already installed."
fi

# ---------------------------------------------------------------------------
# 3. Paquetes
# ---------------------------------------------------------------------------
say "==> Instalando paquetes de los repos oficiales..." "==> Installing packages from the official repos..."
# fzf: Ctrl+R difuso y amigos (se activa desde bash/.bashrc).
# bash-completion: tab para git/systemd/pacman (lo carga /etc/bash.bashrc).
# xdg-desktop-portal-hyprland + -gtk: compartir pantalla en calls (Discord/
#   Meet/OBS) y diálogos de archivos nativos -- sin esto no funcionan.
# polkit-kde-agent: diálogo de contraseña para apps GUI que elevan permisos
#   (se lanza desde hyprland.lua en el autostart).
# btop: monitor de recursos (SUPER+B) / trash-cli: papelera para ranger (tecla D).
# wl-clipboard: da wl-copy/wl-paste, que usa el provider elephant-clipboard
#   para escuchar el portapapeles (su historial vive en
#   ~/.cache/elephant/clipboard.gob, NO en cliphist -- ese paquete no hace
#   falta, quedó descartado tras confirmar que elephant no lo usa).
sudo pacman -S --needed --noconfirm \
    stow nautilus ranger hyprpaper hyprshot swaync ttf-cascadia-code-nerd less \
    bash-completion fzf btop trash-cli wl-clipboard \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk polkit-kde-agent \
    hyprland hyprlock hypridle waybar kitty github-cli postgresql jq make \
    pipewire pipewire-pulse wireplumber brightnessctl playerctl \
    networkmanager network-manager-applet sddm \
    bluez bluez-utils blueman \
    glow graphviz poppler librsvg python-pillow

say "==> Instalando paquetes de AUR (walker, wlogout, elephant, nwg-displays, pwvucontrol)..." \
    "==> Installing AUR packages (walker, wlogout, elephant, nwg-displays, pwvucontrol)..."
# walker (SUPER+R) necesita el backend "elephant" corriendo aparte para poder
# buscar algo -- sin él, walker abre y falla en silencio. Se instalan solo los
# providers que usamos (apps/calc/runner/files/clipboard), no "elephant-all-bin"
# (ese arrastra 1Password/Bitwarden/apt/dnf/rpm/niri, nada de lo que usamos aquí).
# elephant-clipboard: historial del portapapeles en walker (guarda su propio
# historial en ~/.cache/elephant/clipboard.gob, usando wl-paste de wl-clipboard
# -- instalado en los repos oficiales más arriba -- para escuchar copiados).
# nwg-displays: GUI para acomodar/duplicar/extender pantallas (SUPER+P).
paru -S --needed --noconfirm walker wlogout nwg-displays pwvucontrol \
    elephant-bin elephant-desktopapplications-bin elephant-calc-bin \
    elephant-runner-bin elephant-files-bin elephant-clipboard-bin \
    elephant-bluetooth-bin

# ---------------------------------------------------------------------------
# 3a. NetworkManager (obligatorio: sin esto no hay forma de conectarse a
#     redes WiFi nuevas desde la UI)
# ---------------------------------------------------------------------------
say "==> Habilitando NetworkManager (para conectarte a redes WiFi nuevas)..." \
    "==> Enabling NetworkManager (needed to connect to new WiFi networks)..."
sudo systemctl enable --now NetworkManager.service

# ---------------------------------------------------------------------------
# 3b. Docker
# ---------------------------------------------------------------------------
say "==> Instalando Docker..." "==> Installing Docker..."
sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx
sudo systemctl enable --now docker.service

if ! groups "$USER" | grep -q '\bdocker\b'; then
    say "==> Agregando $USER al grupo docker..." "==> Adding $USER to the docker group..."
    sudo usermod -aG docker "$USER"
    say "==> Hecho. Necesitás cerrar sesión y volver a entrar para poder usar 'docker' sin sudo." \
        "==> Done. You need to log out and back in to use 'docker' without sudo."
else
    say "==> $USER ya está en el grupo docker." "==> $USER is already in the docker group."
fi

# ---------------------------------------------------------------------------
# 3c. Claude Code
# ---------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
    say "==> Instalando Claude Code..." "==> Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
else
    say "==> Claude Code ya está instalado ($(claude --version 2>/dev/null))." \
        "==> Claude Code is already installed ($(claude --version 2>/dev/null))."
fi
say "==> Tip: para que los commits/PRs de Claude Code no lleven attribution (Co-Authored-By, etc), poné en ~/.claude/settings.json: \"attribution\": { \"commit\": \"\", \"pr\": \"\" }." \
    "==> Tip: to stop Claude Code commits/PRs from carrying attribution (Co-Authored-By, etc), set in ~/.claude/settings.json: \"attribution\": { \"commit\": \"\", \"pr\": \"\" }."

# ---------------------------------------------------------------------------
# 3d. GitHub CLI (gh)
# ---------------------------------------------------------------------------
# gh ya se instaló arriba (paquete github-cli). El login es interactivo
# (abre el navegador o pide un token) así que no se puede automatizar del
# todo -- si tenés cuenta personal y de trabajo, corré "gh auth login" de
# nuevo después y usá "gh auth switch" para alternar entre ambas.
if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        say "==> gh ya tiene una sesión activa ($(gh auth status 2>&1 | grep 'Logged in' | head -1))." \
            "==> gh already has an active session ($(gh auth status 2>&1 | grep 'Logged in' | head -1))."
    else
        echo ""
        if ask_yn "¿Hacer login con 'gh auth login' ahora? [s/N]: " "Log in with 'gh auth login' now? [y/N]: "; then
            gh auth login
        else
            say "==> Saltado. Corré 'gh auth login' cuando quieras." "==> Skipped. Run 'gh auth login' whenever you want."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 3e. Google Cloud CLI (gcloud) -- instalador oficial de Google, no Arch/AUR
# ---------------------------------------------------------------------------
# Google no publica un paquete pacman propio (el de AUR es mantenido por
# terceros); el método oficial y multi-distro es el tarball + install.sh:
# https://cloud.google.com/sdk/docs/install-sdk
GCLOUD_DIR="$HOME/google-cloud-sdk"
if command -v gcloud >/dev/null 2>&1; then
    say "==> gcloud ya está instalado ($(gcloud --version | head -1))." "==> gcloud is already installed ($(gcloud --version | head -1))."
elif [ -d "$GCLOUD_DIR" ]; then
    say "==> Ya existe $GCLOUD_DIR pero gcloud no está en el PATH -- abrí una terminal nueva." \
        "==> $GCLOUD_DIR already exists but gcloud isn't on the PATH -- open a new terminal."
else
    say "==> Instalando Google Cloud CLI (tarball oficial de Google)..." "==> Installing Google Cloud CLI (official Google tarball)..."
    tmpdir=$(mktemp -d)
    curl -fsSL -o "$tmpdir/gcloud.tar.gz" \
        "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz"
    tar -xf "$tmpdir/gcloud.tar.gz" -C "$HOME"
    "$GCLOUD_DIR/install.sh" --quiet
    rm -rf "$tmpdir"

    # --quiet salta los prompts pero NO edita ~/.bashrc -- lo agregamos a mano.
    if ! grep -q "google-cloud-sdk/path.bash.inc" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<'EOF'

# Google Cloud SDK
if [ -f "$HOME/google-cloud-sdk/path.bash.inc" ]; then
    source "$HOME/google-cloud-sdk/path.bash.inc"
fi
if [ -f "$HOME/google-cloud-sdk/completion.bash.inc" ]; then
    source "$HOME/google-cloud-sdk/completion.bash.inc"
fi
EOF
    fi
    say "==> gcloud instalado en $GCLOUD_DIR y agregado a ~/.bashrc. Abrí una terminal nueva para tenerlo en el PATH." \
        "==> gcloud installed at $GCLOUD_DIR and added to ~/.bashrc. Open a new terminal to get it on the PATH."
fi

# ---------------------------------------------------------------------------
# 3f. Cloud SQL Auth Proxy (/opt/cloud-sql-proxy)
# ---------------------------------------------------------------------------
# Instalado aparte (no como componente de gcloud) para tener un binario fijo
# en /opt y comandos propios en el PATH. update.sh consulta la última versión
# publicada en GitHub (los binarios en sí viven en storage.googleapis.com,
# GitHub solo se usa para saber el tag más reciente) y se puede volver a
# correr cuando quieras para actualizar.
CSP_DIR="/opt/cloud-sql-proxy"
say "==> Instalando/actualizando Cloud SQL Auth Proxy en $CSP_DIR..." "==> Installing/updating Cloud SQL Auth Proxy at $CSP_DIR..."
sudo mkdir -p "$CSP_DIR"
sudo tee "$CSP_DIR/update.sh" > /dev/null <<'CSPEOF'
#!/bin/bash
# /opt/cloud-sql-proxy/update.sh — instala o actualiza a la última versión.
# Uso: sudo cloud-sql-proxy-update
set -e

INSTALL_DIR="/opt/cloud-sql-proxy"
BIN="$INSTALL_DIR/cloud-sql-proxy"

latest="$(curl -fsSL https://api.github.com/repos/GoogleCloudPlatform/cloud-sql-proxy/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
if [ -z "$latest" ]; then
    echo "No se pudo consultar la última versión en GitHub." >&2
    exit 1
fi

current=""
if [ -x "$BIN" ]; then
    current="v$("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi

if [ "$current" = "$latest" ]; then
    echo "cloud-sql-proxy ya está en la última versión ($latest)."
    exit 0
fi

echo "Instalando cloud-sql-proxy $latest (actual: ${current:-ninguna})..."
tmp="$(mktemp)"
curl -fsSL -o "$tmp" "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/$latest/cloud-sql-proxy.linux.amd64"
chmod +x "$tmp"
mv "$tmp" "$BIN"
echo "Listo: $BIN -> $latest"
CSPEOF
sudo chmod +x "$CSP_DIR/update.sh"
sudo "$CSP_DIR/update.sh"

sudo ln -sf "$CSP_DIR/cloud-sql-proxy" /usr/local/bin/cloud-sql-proxy
sudo ln -sf "$CSP_DIR/cloud-sql-proxy" /usr/local/bin/gcloud-proxy
sudo ln -sf "$CSP_DIR/update.sh" /usr/local/bin/cloud-sql-proxy-update
say "==> Comandos listos: cloud-sql-proxy, gcloud-proxy (mismo binario)." \
    "==> Commands ready: cloud-sql-proxy, gcloud-proxy (same binary)."
echo "    $(ask "Para actualizar en el futuro: sudo cloud-sql-proxy-update" "To update in the future: sudo cloud-sql-proxy-update")"

# ---------------------------------------------------------------------------
# 3g. SDDM (login manager) -- tema "tokyo-night" a juego con el resto del
#     escritorio (mismos colores/estilo que hyprlock.conf y waybar/style.css:
#     isla flotante translúcida, reloj grande, acentos azul/violeta). Vive en
#     sddm/tokyo-night/ del repo pero NO se gestiona con Stow porque
#     /usr/share/sddm no está bajo $HOME -- se copia a mano.
# ---------------------------------------------------------------------------
say "==> Instalando tema de SDDM (tokyo-night)..." "==> Installing the SDDM theme (tokyo-night)..."
sudo mkdir -p /usr/share/sddm/themes
sudo rm -rf /usr/share/sddm/themes/tokyo-night
sudo cp -r "$DOTFILES_DIR/sddm/tokyo-night" /usr/share/sddm/themes/tokyo-night

sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-theme.conf > /dev/null <<'EOF'
[Theme]
Current=tokyo-night
CursorTheme=breeze-dark
EOF

if ! systemctl is-enabled sddm.service >/dev/null 2>&1; then
    sudo systemctl enable sddm.service
fi

say "==> Tema de SDDM listo. Para verlo sin cerrar tu sesión actual (abre una ventana de prueba):" \
    "==> SDDM theme ready. To preview it without touching your current session (opens a test window):"
echo "    sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/tokyo-night"
say "    El cambio real se ve la próxima vez que cierres sesión o reinicies." \
    "    The real change shows up next time you log out or reboot."

# ---------------------------------------------------------------------------
# 3h. Bluetooth (bluez + blueman como GUI; el ícono de bandeja "blueman-applet"
#     -- ver el autostart en hyprland.lua -- es el único indicador, sin
#     duplicar módulo en waybar)
# ---------------------------------------------------------------------------
say "==> Habilitando Bluetooth..." "==> Enabling Bluetooth..."
sudo systemctl enable --now bluetooth.service

# ---------------------------------------------------------------------------
# 3i. Térmica de la Legion (opcional) -- solo si el equipo es la Legion Pro 5
#     16ARX8 (detectado por DMI). Instala TLP, el driver de fans
#     LenovoLegionLinux (DKMS por AUR), la curva de ventiladores custom con
#     su servicio de persistencia, y el APST del NVMe en el cmdline de
#     Limine. Diagnóstico completo y cómo revertir: docs/legion/thermal.md.
#     Requiere un reinicio al final para activar todo.
# ---------------------------------------------------------------------------
if grep -qs 'Legion Pro 5 16ARX8' \
        /sys/class/dmi/id/product_name \
        /sys/class/dmi/id/product_family \
        /sys/class/dmi/id/product_version 2>/dev/null; then
    if ask_yn "¿Configurar la térmica de la Legion (TLP + driver de fans + curva custom + APST del NVMe)? Necesita reinicio al final [s/N]: " \
              "Configure the Legion thermal stack (TLP + fan driver + custom curve + NVMe APST)? Needs a reboot afterwards [y/N]: "; then
        bash "$DOTFILES_DIR/legion/install-legion-thermal.sh"
    else
        say "==> Saltado. Podés correrlo cuando quieras: legion/install-legion-thermal.sh" \
            "==> Skipped. You can run it whenever you want: legion/install-legion-thermal.sh"
    fi
else
    say "==> No es una Legion Pro 5 16ARX8: se omite la térmica custom." \
        "==> Not a Legion Pro 5 16ARX8: skipping the custom thermal stack."
fi

# ---------------------------------------------------------------------------
# 4. Tema oscuro por defecto + cursor (sin temas de terceros)
# ---------------------------------------------------------------------------
if command -v gsettings >/dev/null 2>&1; then
    say "==> Aplicando modo oscuro + cursor breeze-dark vía gsettings..." "==> Applying dark mode + breeze-dark cursor via gsettings..."
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme 'breeze-dark' 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 5. Wallpaper placeholder
# ---------------------------------------------------------------------------
mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots"
if [ ! -e "$HOME/Pictures/wallpapers/wallpaper.jpg" ] && [ ! -e "$HOME/Pictures/wallpapers/wallpaper.png" ]; then
    say "==> No hay wallpaper todavía en ~/Pictures/wallpapers/." "==> There's no wallpaper yet in ~/Pictures/wallpapers/."
    say "    Copia ahí tu imagen como 'wallpaper.jpg' (o cambia la ruta en hyprpaper.conf)." \
        "    Copy your image there as 'wallpaper.jpg' (or change the path in hyprpaper.conf)."
fi

# ---------------------------------------------------------------------------
# 6. Backup de archivos reales que choquen, y symlinks con Stow
# ---------------------------------------------------------------------------
# Stow se niega a pisar un archivo real (no symlink) -- movemos a un backup
# cualquier cosa que ya exista en esas rutas antes de crear los symlinks.
say "==> Revisando conflictos antes de aplicar Stow..." "==> Checking for conflicts before applying Stow..."
found_conflict=false
for pkg in $STOW_PACKAGES; do
    while IFS= read -r -d '' f; do
        rel="${f#"$DOTFILES_DIR/$pkg/"}"
        target="$HOME/$rel"
        if [ -e "$target" ]; then
            # Si target ya resuelve (symlink directo, o por un directorio padre
            # "tree-folded" de un Stow anterior) al MISMO archivo del repo, ya
            # está bien enlazado -> no tocar. Sin este chequeo, correr el
            # script una segunda vez sobre un package ya "tree-folded" (p.ej.
            # ~/.config/waybar -> ~/dotfiles/waybar/.config/waybar como UN
            # solo symlink de carpeta) hacía que `-L "$target"` diera falso
            # para cada archivo de adentro (el symlink es el padre, no el
            # archivo) y el `mv` de más abajo movía el archivo REAL del repo
            # al backup -- así es como desaparecieron los archivos de
            # swaync/walker/waybar/wlogout.
            if [ "$(readlink -f "$target" 2>/dev/null)" = "$(readlink -f "$f" 2>/dev/null)" ]; then
                continue
            fi
            if [ ! -L "$target" ]; then
                mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
                mv "$target" "$BACKUP_DIR/$rel"
                echo "    backup: ~/$rel -> $BACKUP_DIR/$rel"
                found_conflict=true
            fi
        fi
    done < <(find "$DOTFILES_DIR/$pkg" -type f -print0)
done
if $found_conflict; then
    say "==> Archivos previos respaldados en $BACKUP_DIR" "==> Previous files backed up at $BACKUP_DIR"
else
    say "==> No había archivos previos en conflicto, no hizo falta backup de archivos." \
        "==> No previous conflicting files, no file backup was needed."
fi

say "==> Aplicando symlinks con Stow ($STOW_PACKAGES)..." "==> Applying symlinks with Stow ($STOW_PACKAGES)..."
cd "$DOTFILES_DIR"
stow -v -t "$HOME" $STOW_PACKAGES

# ---------------------------------------------------------------------------
# 6a. Generar ~/.config/theme/current.css + gtk-{3,4}.0/settings.ini según el
#     modo oscuro/claro recién puesto por gsettings (paso 4). Selector de
#     tema real: botón en waybar (SUPER+click en el ícono de sol/luna),
#     corre ~/.config/hypr/scripts/toggle-theme.sh.
# ---------------------------------------------------------------------------
if [ -x "$HOME/.config/hypr/scripts/apply-theme.sh" ]; then
    say "==> Aplicando paleta de tema (waybar/swaync/kitty/walker + GTK settings.ini)..." \
        "==> Applying theme palette (waybar/swaync/kitty/walker + GTK settings.ini)..."
    "$HOME/.config/hypr/scripts/apply-theme.sh" || true
fi

# ---------------------------------------------------------------------------
# 6b. Preview de markdown/imágenes/PDF/diagramas en ranger (glow, graphviz,
#     poppler y librsvg ya se instalaron arriba; mermaid-cli va por npm/nvm).
#     Config real en ranger/.config/ranger/{rc.conf,scope.sh}.
# ---------------------------------------------------------------------------
say "==> Instalando mermaid-cli (diagramas Mermaid en ranger)..." "==> Installing mermaid-cli (Mermaid diagrams in ranger)..."
ensure_nvm_node
if ! npm list -g @mermaid-js/mermaid-cli >/dev/null 2>&1; then
    npm install -g @mermaid-js/mermaid-cli || \
        say "==> No se pudo instalar mermaid-cli. Los .mmd no van a tener preview hasta instalarlo a mano." \
            "==> Could not install mermaid-cli. .mmd files won't preview until you install it by hand."
fi
say "==> PlantUML necesita Java + el paquete 'plantuml' -- instalalo si lo usás: sudo pacman -S jre-openjdk plantuml" \
    "==> PlantUML needs Java + the 'plantuml' package -- install it if you use it: sudo pacman -S jre-openjdk plantuml"

# ---------------------------------------------------------------------------
# 7. Identidad de git + SSH (opcional -- si decís que no, no se toca nada)
# ---------------------------------------------------------------------------
echo ""
GIT_CONFIGURED=false
if ask_yn "¿Configurar git y SSH ahora (nombre/email + keys)? [s/N]: " \
          "Configure git and SSH now (name/email + keys)? [y/N]: "; then
    GIT_CONFIGURED=true

    say "==> Configuración de git (se guarda en ~/.gitconfig.local, fuera del repo)" \
        "==> Git configuration (saved to ~/.gitconfig.local, outside the repo)"
    read -rp "$(ask "Nombre completo para los commits: " "Full name for commits: ")" git_name
    read -rp "$(ask "Email para los commits: " "Email for commits: ")" git_email

    cat > "$HOME/.gitconfig.local" <<EOF
[user]
    name = $git_name
    email = $git_email
EOF
    say "==> ~/.gitconfig.local creado." "==> ~/.gitconfig.local created."

    # -----------------------------------------------------------------
    # 8. SSH key personal -- el nombre de archivo usa tu usuario de GitHub,
    #    no un "_personal" fijo (así se distingue a simple vista de cuentas
    #    alternativas creadas después, ej. id_ed25519_trabajo).
    # -----------------------------------------------------------------
    read -rp "$(ask "Usuario de GitHub de tu cuenta personal (para nombrar la key, ej. 'daniel-baf'): " \
                    "GitHub username for your personal account (used to name the key, e.g. 'daniel-baf'): ")" gh_user
    gh_user="${gh_user:-personal}"
    SSH_KEY="$HOME/.ssh/id_ed25519_${gh_user}"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if [ -f "$SSH_KEY" ]; then
        say "==> Ya existe $SSH_KEY, no se genera de nuevo." "==> $SSH_KEY already exists, not generating again."
    else
        echo ""
        say "==> Generando key SSH personal (te va a pedir una passphrase, recomendado no dejarla vacía)" \
            "==> Generating personal SSH key (it will ask for a passphrase, recommended not to leave it empty)"
        ssh-keygen -t ed25519 -C "$git_email" -f "$SSH_KEY"
    fi

    if ! grep -q "IdentityFile $SSH_KEY" "$HOME/.ssh/config" 2>/dev/null; then
        cat >> "$HOME/.ssh/config" <<EOF

Host github.com
    IdentityFile $SSH_KEY
    AddKeysToAgent yes
EOF
        chmod 600 "$HOME/.ssh/config"
        say "==> Agregado bloque 'Host github.com' a ~/.ssh/config." "==> Added 'Host github.com' block to ~/.ssh/config."
    fi

    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
    ssh-add "$SSH_KEY" 2>/dev/null || true

    # -----------------------------------------------------------------
    # 8b. Cuenta alternativa de GitHub (ej. trabajo) -- alias configurable,
    #     nada hardcodeado (antes era siempre "_vantum").
    # -----------------------------------------------------------------
    # github.com solo admite una IdentityFile por Host por defecto -> se usa
    # un alias de host ("github-<ext>") para tener dos cuentas de GitHub
    # andando a la vez desde la misma máquina.
    echo ""
    if ask_yn "¿Configurar también otra cuenta de GitHub (ej. de trabajo)? [s/N]: " \
              "Also configure another GitHub account (e.g. work)? [y/N]: "; then
        read -rp "$(ask "Nombre corto para esa cuenta (ej. 'vantum' -> alias SSH 'github-vantum'): " \
                        "Short name for that account (e.g. 'vantum' -> SSH alias 'github-vantum'): ")" alt_ext
        read -rp "$(ask "Email de la cuenta '$alt_ext': " "Email for the '$alt_ext' account: ")" alt_email

        SSH_KEY_ALT="$HOME/.ssh/id_ed25519_${alt_ext}"

        if [ -f "$SSH_KEY_ALT" ]; then
            say "==> Ya existe $SSH_KEY_ALT, no se genera de nuevo." "==> $SSH_KEY_ALT already exists, not generating again."
        else
            say "==> Generando key SSH de la cuenta '$alt_ext' (te va a pedir una passphrase)" \
                "==> Generating SSH key for the '$alt_ext' account (it will ask for a passphrase)"
            ssh-keygen -t ed25519 -C "$alt_email" -f "$SSH_KEY_ALT"
        fi

        if ! grep -q "Host github-$alt_ext" "$HOME/.ssh/config" 2>/dev/null; then
            cat >> "$HOME/.ssh/config" <<EOF

Host github-$alt_ext
    HostName github.com
    User git
    IdentityFile $SSH_KEY_ALT
    AddKeysToAgent yes
EOF
            chmod 600 "$HOME/.ssh/config"
            say "==> Agregado bloque 'Host github-$alt_ext' a ~/.ssh/config." "==> Added 'Host github-$alt_ext' block to ~/.ssh/config."
        fi

        ssh-add "$SSH_KEY_ALT" 2>/dev/null || true
        ALT_EXT="$alt_ext"
        ALT_PUB="$SSH_KEY_ALT.pub"

        # -------------------------------------------------------------
        # 8c. Carpeta para esta cuenta -- en vez de acordarse qué orgs
        #     pertenecen a cada cuenta (y tener que mantener esa lista al
        #     día), la key/email se elige por DÓNDE clonás, no por DE QUIÉN
        #     es el repo. Cualquier repo (de cualquier org, o incluso
        #     personal) clonado dentro de esa carpeta usa esta cuenta.
        #
        #     Funciona con "git clone git@github.com:ORG/repo.git" normal
        #     -- no hace falta el alias github-<ext> a mano -- porque git
        #     ya crea el .git de destino antes de conectarse por red, y
        #     [includeIf "gitdir:..."] matchea contra esa ruta.
        # -------------------------------------------------------------
        echo ""
        read -rp "$(ask "Carpeta donde vas a clonar los repos de '$alt_ext' (ej. ~/work): " \
                        "Folder where you'll clone '$alt_ext' repos (e.g. ~/work): ")" alt_dir
        alt_dir="${alt_dir/#\~/$HOME}"
        if [ -n "$alt_dir" ]; then
            mkdir -p "$alt_dir"
            ALT_GITCONFIG="$HOME/.gitconfig-$alt_ext"
            # -F /dev/null es necesario: sin eso, ssh además suma el
            # IdentityFile del bloque "Host github.com" de ~/.ssh/config (la
            # key personal) a la lista de identidades candidatas -- si esa
            # key también está registrada en GitHub, gana ella igual aunque
            # acá se especifique "-i" con la de trabajo. -F /dev/null hace
            # que ssh ignore por completo ~/.ssh/config para esta conexión,
            # dejando SOLO la identidad pasada por -i.
            cat > "$ALT_GITCONFIG" <<EOF
[user]
    email = $alt_email
[core]
    sshCommand = ssh -F /dev/null -i $SSH_KEY_ALT -o IdentitiesOnly=yes
EOF
            if ! grep -qF "gitdir:$alt_dir/" "$HOME/.gitconfig.local" 2>/dev/null; then
                cat >> "$HOME/.gitconfig.local" <<EOF

[includeIf "gitdir:$alt_dir/"]
    path = $ALT_GITCONFIG
EOF
                say "==> Todo lo que clones dentro de $alt_dir/ va a usar la cuenta '$alt_ext' (key + email) automáticamente." \
                    "==> Everything you clone inside $alt_dir/ will automatically use the '$alt_ext' account (key + email)."
            fi
            ALT_DIR="$alt_dir"
        fi
    fi
else
    say "==> Saltado: git/SSH no configurado (corré el script de nuevo cuando quieras)." \
        "==> Skipped: git/SSH not configured (run the script again whenever you want)."
fi

# ---------------------------------------------------------------------------
# 9. Apps opcionales -- sin preguntas: si falta se instala, si ya está se
#    salta. La idea es poder correr install.sh las veces que sea sin
#    babysittearlo (idempotente de punta a punta).
# ---------------------------------------------------------------------------
say "==> Apps opcionales (se instalan las que falten)..." \
    "==> Optional apps (missing ones get installed)..."

# pacman y paru comparten la base de datos local -> sirve para ambos.
have_pkg() {
    pacman -Q "$1" >/dev/null 2>&1
}

# install_pacman <pkg> / install_aur <pkg> -- nunca abortan el script.
install_pacman() {
    if have_pkg "$1"; then
        say "==> $1 ya está instalado." "==> $1 is already installed."
        return 0
    fi
    if ! sudo pacman -S --needed --noconfirm "$1"; then
        say "==> No se pudo instalar '$1'. Instalalo a mano cuando quieras: sudo pacman -S $1" \
            "==> Could not install '$1'. Install it manually whenever you want: sudo pacman -S $1"
    fi
}

install_aur() {
    if have_pkg "$1"; then
        say "==> $1 ya está instalado." "==> $1 is already installed."
        return 0
    fi
    if ! paru -S --needed --noconfirm "$1"; then
        say "==> No se pudo instalar '$1'. Instalalo a mano cuando quieras: paru -S $1" \
            "==> Could not install '$1'. Install it manually whenever you want: paru -S $1"
    fi
}

say "-- Grabación/streaming --" "-- Recording/streaming --"
install_pacman obs-studio

say "-- Navegador y música --" "-- Browser and music --"
install_aur google-chrome
if ! have_pkg spotify-launcher; then
    install_aur spotify-launcher
    say "    (Primera vez: corré 'spotify-launcher' para que baje el cliente oficial.)" \
        "    (First run: run 'spotify-launcher' so it downloads the official client.)"
fi

say "-- Herramientas de IA (CLI) --" "-- AI tools (CLI) --"
install_pacman opencode
if ! command -v playwright >/dev/null 2>&1; then
    ensure_nvm_node
    if npm install -g playwright; then
        playwright install chromium || \
            say "==> Playwright CLI instalado, pero falló la descarga del browser Chromium. Corré 'playwright install chromium' a mano." \
                "==> Playwright CLI installed, but downloading the Chromium browser failed. Run 'playwright install chromium' by hand."
    else
        say "==> No se pudo instalar Playwright CLI vía npm." "==> Could not install Playwright CLI via npm."
    fi
else
    say "==> Playwright CLI ya está instalado." "==> Playwright CLI is already installed."
fi
if ! command -v codex >/dev/null 2>&1; then
    ensure_nvm_node
    if ! npm install -g @openai/codex; then
        say "==> No se pudo instalar Codex CLI vía npm." "==> Could not install Codex CLI via npm."
    fi
else
    say "==> Codex CLI ya está instalado." "==> Codex CLI is already installed."
fi
if have_pkg antigravity-bin; then
    say "==> antigravity-bin ya está instalado." "==> antigravity-bin is already installed."
elif paru -Si antigravity-bin >/dev/null 2>&1; then
    # Nombre de paquete AUR sin confirmar al 100% (herramienta muy nueva) --
    # se verifica antes de intentar instalar para no cortar el script.
    install_aur antigravity-bin
else
    say "==> No encontré 'antigravity-bin' en AUR. Instalala a mano: https://antigravity.google/" \
        "==> Could not find 'antigravity-bin' in AUR. Install it manually: https://antigravity.google/"
fi
if ! command -v agy >/dev/null 2>&1; then
    say "==> Instalando la CLI de Antigravity (agy)..." "==> Installing the Antigravity CLI (agy)..."
    if ! curl -fsSL https://antigravity.google/cli/install.sh | bash; then
        say "==> No se pudo instalar la CLI de Antigravity. Instalala a mano: curl -fsSL https://antigravity.google/cli/install.sh | bash" \
            "==> Could not install the Antigravity CLI. Install it manually: curl -fsSL https://antigravity.google/cli/install.sh | bash"
    fi
else
    say "==> La CLI de Antigravity (agy) ya está instalada." "==> The Antigravity CLI (agy) is already installed."
fi

say "-- IDEs / editores --" "-- IDEs / editors --"
install_aur cursor-bin
install_aur visual-studio-code-bin
# datagrip solo no abre -- hace falta también datagrip-jre (el runtime).
install_aur datagrip
install_aur datagrip-jre

echo ""
echo "=============================================================="
say " Listo. Pasos que te faltan a mano:" " Done. Steps left for you to do by hand:"
echo ""
if $GIT_CONFIGURED; then
    say " 1) Pega esta clave pública (personal) en GitHub -> Settings -> SSH keys:" \
        " 1) Paste this public key (personal) into GitHub -> Settings -> SSH keys:"
    echo ""
    cat "$SSH_KEY.pub"
    if [ -n "${ALT_PUB:-}" ]; then
        echo ""
        say "    Y esta otra en la cuenta de GitHub '$ALT_EXT':" "    And this other one into the '$ALT_EXT' GitHub account:"
        echo ""
        cat "$ALT_PUB"
        echo ""
        if [ -n "${ALT_DIR:-}" ]; then
            say "    Cloná los repos de esa cuenta DENTRO de $ALT_DIR/ -- ahí adentro se usa" \
                "    Clone that account's repos INSIDE $ALT_DIR/ -- inside that folder it"
            say "    la key y el email de '$ALT_EXT' solos, sea cual sea el org/dueño del repo:" \
                "    automatically uses the '$ALT_EXT' key and email, whatever the repo's org/owner is:"
            echo "    git clone git@github.com:ORG/repo.git   # (parado adentro de $ALT_DIR/)"
        else
            say "    Para clonar repos de esa cuenta usa el alias, no github.com directo:" \
                "    To clone repos from that account use the alias, not github.com directly:"
            echo "    git clone git@github-$ALT_EXT:ORG/repo.git"
        fi
    fi
else
    say " 1) Git/SSH no se configuró en esta corrida -- corré ./install.sh de nuevo cuando quieras." \
        " 1) Git/SSH was not configured in this run -- run ./install.sh again whenever you want."
fi
echo ""
say " 2) Cierra sesión y vuelve a entrar a Hyprland (obligatorio: se" \
    " 2) Log out and back into Hyprland (mandatory: it went from"
say "    pasó de hyprland.conf a hyprland.lua, hyprctl reload no alcanza)." \
    "    hyprland.conf to hyprland.lua, hyprctl reload isn't enough)."
if $GIT_CONFIGURED; then
    echo ""
    say " 3) Prueba la key personal: ssh -T git@github.com" " 3) Test the personal key: ssh -T git@github.com"
    if [ -n "${ALT_PUB:-}" ]; then
        say "    Prueba la otra key: ssh -T git@github-$ALT_EXT" "    Test the other key: ssh -T git@github-$ALT_EXT"
    fi
fi
if $found_conflict; then
    echo ""
    say " Backup de tus archivos previos (por si algo no te convence): $BACKUP_DIR" \
        " Backup of your previous files (in case something doesn't convince you): $BACKUP_DIR"
fi
echo "=============================================================="
