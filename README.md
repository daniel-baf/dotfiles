# dotfiles

Config de Hyprland (Legion Pro 7, solo NVIDIA) gestionada con [GNU Stow](https://www.gnu.org/software/stow/).

## Qué incluye

| Carpeta   | Qué configura                                  |
|-----------|-------------------------------------------------|
| `git`     | `~/.gitconfig` (sin datos personales, ver abajo) |
| `kitty`   | Terminal, tema Tokyo Night                       |
| `hypr`    | `hyprland.lua`, `hyprlock`, `hypridle`, `hyprpaper` |
| `waybar`  | Barra superior (incluye el botón de tema oscuro/claro) |
| `theme`   | Paleta compartida oscura/clara (Tokyo Night / Tokyo Night Day) que importan waybar, swaync, wlogout y walker |
| `walker`  | Launcher (`SUPER + R`)                           |
| `swaync`  | Notificaciones                                   |
| `wlogout` | Menú de apagado/logout (`SUPER + M`)             |
| `sddm`    | Tema de la pantalla de login (`tokyo-night`), no va con Stow: `install.sh` lo copia a `/usr/share/sddm/themes/` |
| `legion`  | Térmica de la Legion Pro 5 16ARX8 (TLP + driver de fans + curva custom + APST del NVMe), no va con Stow: `install.sh` pregunta y corre `legion/install-legion-thermal.sh` — diagnóstico completo en `docs/legion/thermal.md` |
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

## Tema oscuro/claro

Botón en la punta derecha de waybar (ícono de luna/sol) togglea entre Tokyo
Night (oscuro) y Tokyo Night Day (claro) en waybar, swaync, wlogout, walker
y kitty (esto último solo afecta a ventanas nuevas). La fuente de verdad es
`gsettings org.gnome.desktop.interface color-scheme`; todo lo demás lo
reaplica `~/.config/hypr/scripts/apply-theme.sh` (idempotente, también corre
solo en cada arranque de Hyprland para que los bordes de ventana no vuelvan
a oscuro en cada relogin).

De paso, ese mismo script arregla que Chrome (y cualquier app GTK) detecte
mal `prefers-color-scheme` en modo "system": sin `~/.config/gtk-{3,4}.0/settings.ini`
(que no existe por defecto en Hyprland, sin xsettings daemon), GTK nunca se
enteraba del modo oscuro aunque gsettings estuviera bien. `apply-theme.sh`
genera esos `settings.ini` a mano y los mantiene sincronizados con el toggle.

## Por qué `[user]` no está en `git/.gitconfig`

`git/.gitconfig` incluye `~/.gitconfig.local`, un archivo que vive **fuera**
de este repo y que `install.sh` genera en cada máquina. Así el repo se puede
hacer público (o subir como gist) sin filtrar tu nombre/email real.
