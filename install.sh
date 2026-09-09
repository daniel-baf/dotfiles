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
        *) echo "Uso: ./install.sh [--skip-backup]"; exit 1 ;;
    esac
done

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOW_PACKAGES="git kitty hypr waybar walker swaync wlogout"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

echo "==> Dotfiles en: $DOTFILES_DIR"

# ---------------------------------------------------------------------------
# 0. Backup de seguridad antes de tocar nada en $HOME (opcional: --skip-backup)
# ---------------------------------------------------------------------------
# Tu / (y @home) son btrfs con subvolúmenes (ver docs/hyprland/instalacion.md,
# paso 3) -> si detectamos btrfs, además del backup de archivos de abajo,
# sacamos un snapshot de solo lectura de /home completo como red de seguridad.
if $SKIP_BACKUP; then
    echo "==> --skip-backup: se omite el snapshot btrfs de \$HOME."
elif [ "$(stat -f --format=%T "$HOME" 2>/dev/null)" = "btrfs" ] && command -v btrfs >/dev/null 2>&1; then
    echo "==> \$HOME es btrfs."
    if [ -d /.snapshots ]; then
        snap_name="home-preinstall-$(date +%Y%m%d-%H%M%S)"
        echo "==> Creando snapshot de solo lectura: /.snapshots/$snap_name"
        if sudo btrfs subvolume snapshot -r /home "/.snapshots/$snap_name"; then
            echo "==> Snapshot listo. Para volver atrás si algo sale mal:"
            echo "    sudo btrfs subvolume snapshot /.snapshots/$snap_name /home_restaurado"
        else
            echo "==> No se pudo crear el snapshot btrfs, seguimos solo con el backup de archivos."
        fi
    else
        echo "==> No encontré /.snapshots montado, seguimos solo con el backup de archivos."
    fi
else
    echo "==> \$HOME no es btrfs (o falta el binario 'btrfs'): solo se hace el backup de archivos."
fi

# ---------------------------------------------------------------------------
# 1. git
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    echo "==> Instalando git..."
    sudo pacman -S --needed --noconfirm git
else
    echo "==> git ya está instalado ($(git --version))."
fi

# ---------------------------------------------------------------------------
# 2. paru (necesario para walker y wlogout, que solo están en AUR)
# ---------------------------------------------------------------------------
if ! command -v paru >/dev/null 2>&1; then
    echo "==> Instalando paru..."
    sudo pacman -S --needed --noconfirm base-devel
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
    (cd "$tmpdir/paru" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
else
    echo "==> paru ya está instalado."
fi

# ---------------------------------------------------------------------------
# 3. Paquetes
# ---------------------------------------------------------------------------
echo "==> Instalando paquetes de los repos oficiales..."
sudo pacman -S --needed --noconfirm \
    stow nautilus ranger hyprpaper hyprshot swaync ttf-cascadia-code-nerd \
    hyprland hyprlock hypridle waybar kitty github-cli postgresql \
    pipewire pipewire-pulse wireplumber brightnessctl playerctl

echo "==> Instalando paquetes de AUR (walker, wlogout, elephant)..."
# walker (SUPER+R) necesita el backend "elephant" corriendo aparte para poder
# buscar algo -- sin él, walker abre y falla en silencio. Se instalan solo los
# providers que usamos (apps/calc/runner/files), no "elephant-all-bin" (ese
# arrastra 1Password/Bitwarden/apt/dnf/rpm/niri, nada de lo que usamos aquí).
paru -S --needed --noconfirm walker wlogout \
    elephant-bin elephant-desktopapplications-bin elephant-calc-bin \
    elephant-runner-bin elephant-files-bin

# ---------------------------------------------------------------------------
# 3b. Docker
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "==> Instalando Docker..."
    sudo pacman -S --needed --noconfirm docker docker-compose
    sudo systemctl enable --now docker.service
else
    echo "==> Docker ya está instalado ($(docker --version))."
fi

if ! groups "$USER" | grep -q '\bdocker\b'; then
    echo "==> Agregando $USER al grupo docker..."
    sudo usermod -aG docker "$USER"
    echo "==> Hecho. Necesitás cerrar sesión y volver a entrar para poder usar 'docker' sin sudo."
else
    echo "==> $USER ya está en el grupo docker."
fi

# ---------------------------------------------------------------------------
# 3c. Claude Code
# ---------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
    echo "==> Instalando Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "==> Claude Code ya está instalado ($(claude --version 2>/dev/null))."
fi

# ---------------------------------------------------------------------------
# 3d. GitHub CLI (gh)
# ---------------------------------------------------------------------------
# gh ya se instaló arriba (paquete github-cli). El login es interactivo
# (abre el navegador o pide un token) así que no se puede automatizar del
# todo -- si tenés cuenta personal y de trabajo, corré "gh auth login" de
# nuevo después y usá "gh auth switch" para alternar entre ambas.
if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        echo "==> gh ya tiene una sesión activa ($(gh auth status 2>&1 | grep 'Logged in' | head -1))."
    else
        echo ""
        read -rp "¿Hacer login con 'gh auth login' ahora? [s/N]: " setup_gh
        if [[ "$setup_gh" =~ ^[sSyY] ]]; then
            gh auth login
        else
            echo "==> Saltado. Corré 'gh auth login' cuando quieras."
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
    echo "==> gcloud ya está instalado ($(gcloud --version | head -1))."
elif [ -d "$GCLOUD_DIR" ]; then
    echo "==> Ya existe $GCLOUD_DIR pero gcloud no está en el PATH -- abrí una terminal nueva."
else
    echo "==> Instalando Google Cloud CLI (tarball oficial de Google)..."
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
    echo "==> gcloud instalado en $GCLOUD_DIR y agregado a ~/.bashrc. Abrí una terminal nueva para tenerlo en el PATH."
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
echo "==> Instalando/actualizando Cloud SQL Auth Proxy en $CSP_DIR..."
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
echo "==> Comandos listos: cloud-sql-proxy, gcloud-proxy (mismo binario)."
echo "    Para actualizar en el futuro: sudo cloud-sql-proxy-update"

# ---------------------------------------------------------------------------
# 4. Tema oscuro por defecto + cursor (sin temas de terceros)
# ---------------------------------------------------------------------------
if command -v gsettings >/dev/null 2>&1; then
    echo "==> Aplicando modo oscuro + cursor breeze-dark vía gsettings..."
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme 'breeze-dark' 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 5. Wallpaper placeholder
# ---------------------------------------------------------------------------
mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots"
if [ ! -e "$HOME/Pictures/wallpapers/wallpaper.jpg" ] && [ ! -e "$HOME/Pictures/wallpapers/wallpaper.png" ]; then
    echo "==> No hay wallpaper todavía en ~/Pictures/wallpapers/."
    echo "    Copia ahí tu imagen como 'wallpaper.jpg' (o cambia la ruta en hyprpaper.conf)."
fi

# ---------------------------------------------------------------------------
# 6. Backup de archivos reales que choquen, y symlinks con Stow
# ---------------------------------------------------------------------------
# Stow se niega a pisar un archivo real (no symlink) -- movemos a un backup
# cualquier cosa que ya exista en esas rutas antes de crear los symlinks.
echo "==> Revisando conflictos antes de aplicar Stow..."
found_conflict=false
for pkg in $STOW_PACKAGES; do
    while IFS= read -r -d '' f; do
        rel="${f#"$DOTFILES_DIR/$pkg/"}"
        target="$HOME/$rel"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
            mv "$target" "$BACKUP_DIR/$rel"
            echo "    backup: ~/$rel -> $BACKUP_DIR/$rel"
            found_conflict=true
        fi
    done < <(find "$DOTFILES_DIR/$pkg" -type f -print0)
done
if $found_conflict; then
    echo "==> Archivos previos respaldados en $BACKUP_DIR"
else
    echo "==> No había archivos previos en conflicto, no hizo falta backup de archivos."
fi

echo "==> Aplicando symlinks con Stow ($STOW_PACKAGES)..."
cd "$DOTFILES_DIR"
stow -v -t "$HOME" $STOW_PACKAGES

# ---------------------------------------------------------------------------
# 7. Identidad de git (se pide siempre, nunca se guarda en el repo)
# ---------------------------------------------------------------------------
echo ""
echo "==> Configuración de git (se guarda en ~/.gitconfig.local, fuera del repo)"
read -rp "Nombre completo para los commits: " git_name
read -rp "Email para los commits: " git_email

cat > "$HOME/.gitconfig.local" <<EOF
[user]
    name = $git_name
    email = $git_email
EOF
echo "==> ~/.gitconfig.local creado."

# ---------------------------------------------------------------------------
# 8. SSH key personal
# ---------------------------------------------------------------------------
SSH_KEY="$HOME/.ssh/id_ed25519_personal"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$SSH_KEY" ]; then
    echo "==> Ya existe $SSH_KEY, no se genera de nuevo."
else
    echo ""
    echo "==> Generando key SSH personal (te va a pedir una passphrase, recomendado no dejarla vacía)"
    ssh-keygen -t ed25519 -C "$git_email" -f "$SSH_KEY"
fi

if ! grep -q "IdentityFile $SSH_KEY" "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" <<EOF

Host github.com
    IdentityFile $SSH_KEY
    AddKeysToAgent yes
EOF
    chmod 600 "$HOME/.ssh/config"
    echo "==> Agregado bloque 'Host github.com' a ~/.ssh/config."
fi

eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
ssh-add "$SSH_KEY" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8b. SSH key de la cuenta de trabajo (_vantum)
# ---------------------------------------------------------------------------
# github.com solo admite una IdentityFile por Host por defecto -> se usa un
# alias de host ("github-vantum") para poder tener las dos cuentas de GitHub
# (personal y trabajo) andando a la vez desde la misma máquina.
echo ""
read -rp "¿Configurar también la cuenta de trabajo _vantum? [s/N]: " setup_vantum
if [[ "$setup_vantum" =~ ^[sSyY] ]]; then
    read -rp "Email de la cuenta de trabajo (_vantum): " vantum_email
    SSH_KEY_VANTUM="$HOME/.ssh/id_ed25519_vantum"

    if [ -f "$SSH_KEY_VANTUM" ]; then
        echo "==> Ya existe $SSH_KEY_VANTUM, no se genera de nuevo."
    else
        echo "==> Generando key SSH de trabajo (te va a pedir una passphrase)"
        ssh-keygen -t ed25519 -C "$vantum_email" -f "$SSH_KEY_VANTUM"
    fi

    if ! grep -q "Host github-vantum" "$HOME/.ssh/config" 2>/dev/null; then
        cat >> "$HOME/.ssh/config" <<EOF

Host github-vantum
    HostName github.com
    User git
    IdentityFile $SSH_KEY_VANTUM
    AddKeysToAgent yes
EOF
        chmod 600 "$HOME/.ssh/config"
        echo "==> Agregado bloque 'Host github-vantum' a ~/.ssh/config."
    fi

    ssh-add "$SSH_KEY_VANTUM" 2>/dev/null || true
    VANTUM_PUB="$SSH_KEY_VANTUM.pub"
fi

echo ""
echo "=============================================================="
echo " Listo. Pasos que te faltan a mano:"
echo ""
echo " 1) Pega esta clave pública (personal) en GitHub -> Settings -> SSH keys:"
echo ""
cat "$SSH_KEY.pub"
if [ -n "${VANTUM_PUB:-}" ]; then
    echo ""
    echo "    Y esta otra en la cuenta de GitHub de trabajo (_vantum):"
    echo ""
    cat "$VANTUM_PUB"
    echo ""
    echo "    Para clonar repos de trabajo usa el alias, no github.com directo:"
    echo "    git clone git@github-vantum:ORG/repo.git"
fi
echo ""
echo " 2) Cierra sesión y vuelve a entrar a Hyprland (obligatorio: se"
echo "    pasó de hyprland.conf a hyprland.lua, hyprctl reload no alcanza)."
echo ""
echo " 3) Prueba la key personal: ssh -T git@github.com"
if [ -n "${VANTUM_PUB:-}" ]; then
    echo "    Prueba la key de trabajo: ssh -T git@github-vantum"
fi
if $found_conflict; then
    echo ""
    echo " Backup de tus archivos previos (por si algo no te convence): $BACKUP_DIR"
fi
echo "=============================================================="
