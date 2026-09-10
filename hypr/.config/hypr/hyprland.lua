-- ~/.config/hypr/hyprland.lua — gestionado desde ~/dotfiles (Stow)
-- Legion Pro 7 Gen 8, solo NVIDIA (RTX 4060), Hyprland 0.56+
-- Ver docs/hyprland/instalacion.md (paso 9 y siguientes) para el porqué de cada bloque.

------------------------------
---- VARIABLES DE ENTORNO ----
------------------------------

-- Obligatorias para que Wayland use bien la GPU NVIDIA (sin iGPU, no hay PRIME offload)
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("NVD_BACKEND", "direct")

-- Cursor
hl.env("XCURSOR_THEME", "breeze-dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "breeze-dark")
hl.env("HYPRCURSOR_SIZE", "24")

-- Qt siguiendo el theme oscuro del sistema (sin Kvantum, sin GTK_THEME forzado)
hl.env("QT_QPA_PLATFORMTHEME", "gtk2")

------------------
---- MONITOR -----
------------------

-- eDP-1, panel único del Legion (dato real: hyprctl monitors).
-- scale = 1.25, no 1.2: 2560x1600 / 1.2 = 2133.33x1333.33 (no da píxeles
-- lógicos enteros) -> Hyprland lo rechaza y aplica 1.25 (2048x1280, entero)
-- solo, avisando en cada arranque. 1.25 evita ese aviso.
hl.monitor({ output = "eDP-1", mode = "2560x1600@165", position = "0x0", scale = 1.25 })

---------------------
---- MY PROGRAMS ----
---------------------

local mainMod     = "SUPER"
local terminal    = "kitty"
local fileManager = "nautilus"
local fileManagerCli = "ranger"
local menu        = "walker"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("pkill waybar; waybar")
end)
hl.on("hyprland.start", function()
    hl.exec_cmd("hypridle")
end)
hl.on("hyprland.start", function()
    -- El paquete de hyprpaper instalado no aplica el wallpaper si se declara
    -- en hyprpaper.conf (bug: "preload" por IPC falla y las directivas del
    -- config se leen antes de que el output esté listo). Por eso se lanza
    -- hyprpaper solo con IPC activado y se manda "wallpaper" por hyprctl
    -- con reintentos hasta que el socket IPC responde. Ver hyprpaper.conf.
    hl.exec_cmd([[
        pkill hyprpaper
        hyprpaper -c ~/.config/hypr/hyprpaper.conf &
        for i in $(seq 1 20); do
            hyprctl hyprpaper wallpaper ",$HOME/Pictures/wallpapers/wallpaper.jpg" >/dev/null 2>&1 && break
            sleep 0.3
        done
    ]])
end)
hl.on("hyprland.start", function()
    hl.exec_cmd("swaync")
end)
hl.on("hyprland.start", function()
    -- walker (SUPER+R) necesita elephant corriendo de fondo como backend de datos
    -- (paquetes AUR: elephant-bin, elephant-desktopapplications-bin, elephant-calc-bin,
    --  elephant-runner-bin, elephant-files-bin — instalados por install.sh)
    -- ~/.config/elephant/elephant.toml (paquete stow "elephant") desactiva el
    -- auto_detect_launch_prefix: sin eso, elephant envuelve cada app con
    -- "systemd-run --user", que sin UWSM no hereda WAYLAND_DISPLAY/XDG_RUNTIME_DIR/
    -- PATH -- las apps abrían pero sin audio (les pasaba a Spotify, Discord, etc.)
    hl.exec_cmd("pkill elephant; elephant")
end)
hl.on("hyprland.start", function()
    -- servicio de walker: precarga la ventana para que SUPER+R la muestre al instante
    hl.exec_cmd("pkill -f 'walker --gapplication-service'; walker --gapplication-service")
end)
hl.on("hyprland.start", function()
    -- ícono de red en la bandeja (tray de waybar) para conectarse a redes WiFi nuevas
    hl.exec_cmd("pkill nm-applet; nm-applet --indicator")
end)

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 12,
        border_size = 2,
        col = {
            active_border   = { colors = {"rgba(7aa2f7ee)", "rgba(bb9af7ee)"}, angle = 45 },
            inactive_border = "rgba(292e42aa)",
        },
        resize_on_border = true,
        layout = "dwindle",
    },

    decoration = {
        rounding = 10,
        active_opacity   = 1.0,
        inactive_opacity = 0.95,

        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = 0xee1a1b26,
        },

        -- Blur real detrás de ventanas con opacidad < 1 (kitty, walker, swaync...)
        blur = {
            enabled  = true,
            size     = 6,
            passes   = 3,
            vibrancy = 0.17,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.config({
    dwindle = {
        preserve_split = true,
    },
})

-- Layout de teclado por defecto: "latam" (ES) o "us" (EN) según lo elegido
-- en install.sh, guardado en ~/.config/hypr/.kb_layout (fuera del repo, no
-- gestionado por Stow). SUPER+Espacio alterna entre los dos igual.
local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("l")
    f:close()
    return line
end
local kbLayout = read_first_line(os.getenv("HOME") .. "/.config/hypr/.kb_layout") or "latam,us"

hl.config({
    input = {
        kb_layout = kbLayout,
        kb_options = "grp:win_space_toggle",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
        },
    },
})

-- Gesto de 4 dedos en el touchpad para cambiar de workspace
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace",
})

---------------------
---- KEYBINDINGS ----
---------------------

-- Apps
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("wlogout"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(terminal .. " " .. fileManagerCli))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "d" }))

-- Mover ventana (intercambia de lugar con la vecina en esa dirección)
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "d" }))

-- Mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Workspaces 1-9 y 0 -> 10
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. tostring(i),         hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind(mainMod .. " + SHIFT + " .. tostring(i), hl.dsp.window.move({ workspace = tostring(i) }))
end
hl.bind(mainMod .. " + 0",         hl.dsp.focus({ workspace = "10" }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = "10" }))

-- Scroll del mouse cambia de workspace
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e+1" }))

-- Workspace especial (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Pantallas: SUPER+P abre la GUI (nwg-displays) para acomodar/duplicar/
-- extender a mano; SUPER+SHIFT+P alterna directo entre extender y duplicar.
hl.bind(mainMod .. " + P",         hl.dsp.exec_cmd("nwg-displays"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-display-mode.sh"))

-- Screenshots (hyprshot)
hl.bind("Print",                hl.dsp.exec_cmd("hyprshot -m output -o ~/Pictures/Screenshots"))
hl.bind(mainMod .. " + Print",   hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))

-- Multimedia / brillo (funcionan también sobre hyprlock con locked = true)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { locked = true, repeating = true })

-- Player (playerctl)
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"),       { locked = true })

--------------------------------
---- WINDOWS Y WORKSPACES -----
--------------------------------

-- Ignora eventos de "maximize" de apps (recomendado por el ejemplo oficial de Hyprland)
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
