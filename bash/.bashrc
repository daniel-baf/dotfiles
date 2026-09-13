# ~/.bashrc — gestionado desde ~/dotfiles (Stow)
#
# Nota: bash-completion no se sourcea acá -- en Arch lo carga solo
# /etc/bash.bashrc si el paquete 'bash-completion' está instalado.

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# -------------------------
# -- Look & feel básicos --
# -------------------------
alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# Alias útiles
alias ll='ls -lah'
alias gs='git status'

# Steam corre por XWayland (sin soporte nativo de Wayland) y con el scale
# 1.25 del panel se ve chico o borroso según cómo se lance -- el fix real es
# xwayland.force_zero_scaling en hyprland.lua (nítido, pero XWayland queda
# "ciego" al escalado), y esta variable hace que la UI propia de Steam (no
# los juegos) compense con su propio 1.25 para no verse chica. Mismo fix
# aplicado al .desktop (steam/.local/share/applications/steam.desktop) para
# cuando se abre desde walker.
alias steam='STEAM_FORCE_DESKTOPUI_SCALING=1.25 steam'

# -------------------------
# -- Entorno --
# -------------------------
export PATH="$HOME/.local/bin:$PATH"

# -------------------------
# -- Historial --
# -------------------------
# Todas las terminales suman al mismo archivo y sin duplicados:
# lo que escribiste en una terminal queda disponible en las otras.
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoredups
shopt -s histappend

# -------------------------
# -- fzf (búsqueda difusa) --
# -------------------------
# Ctrl+R: historial difuso | Ctrl+T: insertar archivo | Alt+C: cd difuso
if [ -f /usr/share/fzf/key-bindings.bash ]; then
    source /usr/share/fzf/key-bindings.bash
fi
if [ -f /usr/share/fzf/completion.bash ]; then
    source /usr/share/fzf/completion.bash
fi

# -------------------------
# -- Google Cloud SDK --
# -------------------------
# (install.sh también busca este bloque para no duplicarlo si ya existe)
if [ -f "$HOME/google-cloud-sdk/path.bash.inc" ]; then
    source "$HOME/google-cloud-sdk/path.bash.inc"
fi
if [ -f "$HOME/google-cloud-sdk/completion.bash.inc" ]; then
    source "$HOME/google-cloud-sdk/completion.bash.inc"
fi

# -------------------------
# -- nvm / Node --
# -------------------------
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
