# dotfiles

Config de Hyprland (Legion Pro 7, solo NVIDIA) gestionada con [GNU Stow](https://www.gnu.org/software/stow/).

## Qué incluye

| Carpeta   | Qué configura                                  |
|-----------|-------------------------------------------------|
| `git`     | `~/.gitconfig` (sin datos personales, ver abajo) |
| `kitty`   | Terminal, tema Tokyo Night                       |
| `hypr`    | `hyprland.lua`, `hyprlock`, `hypridle`, `hyprpaper` |
| `waybar`  | Barra superior                                   |
| `walker`  | Launcher (`SUPER + R`)                           |
| `swaync`  | Notificaciones                                   |
| `wlogout` | Menú de apagado/logout (`SUPER + M`)             |
| `sddm`    | Tema de la pantalla de login (`tokyo-night`), no va con Stow: `install.sh` lo copia a `/usr/share/sddm/themes/` |
| `claude`  | Skills de Claude Code (`~/.claude/skills/`), p.ej. `caveman` (modo de respuestas comprimido) |
| `caveman` | El mismo modo "caveman", pero para Codex CLI (`~/.codex/AGENTS.md`), OpenCode (`~/.config/opencode/AGENTS.md`) y Antigravity CLI (`~/.gemini/GEMINI.md`) -- gateado para que solo se active si lo pedís en la conversación, ya que esas herramientas no tienen sistema de skills bajo demanda como Claude Code |

## Uso en una PC nueva

```bash
git clone <url-de-este-repo> ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` instala los paquetes que faltan (repos oficiales + AUR vía `paru`),
aplica los symlinks con Stow, y pide interactivamente tu nombre/email de git
y genera una key SSH nueva (`~/.ssh/id_ed25519_personal`) — nada de eso queda
guardado en este repo.

Después de correrlo: **cerrá sesión y volvé a entrar a Hyprland** (el cambio de
`hyprland.conf` a `hyprland.lua` no se aplica con `hyprctl reload`).

## Por qué `[user]` no está en `git/.gitconfig`

`git/.gitconfig` incluye `~/.gitconfig.local`, un archivo que vive **fuera**
de este repo y que `install.sh` genera en cada máquina. Así el repo se puede
hacer público (o subir como gist) sin filtrar tu nombre/email real.
