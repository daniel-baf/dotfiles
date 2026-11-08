# Curva de ventiladores de la GPU NVIDIA en Hyprland (Wayland)

> Punto de partida: *"`nvidia-settings` sin sudo no me deja cambiar la
> velocidad del fan, y `sudo nvidia-settings` falla con `Authorization
> required` / `The control display is undefined`."*

## Por qué falla cada cosa

| Intento | Error | Causa |
|---------|-------|-------|
| `nvidia-settings` (usuario) | el control del fan aparece deshabilitado o el valor no cambia | `GPUFanControlState` y `GPUTargetFanSpeed` son **escrituras privilegiadas** de NV-CONTROL. Sin root se pueden leer, no escribir. |
| `sudo nvidia-settings` | `Authorization required, but no authorization protocol specified` + `The control display is undefined` | `sudo` resetea el entorno: `DISPLAY` y `XAUTHORITY` no se heredan. `nvidia-settings` cae al display por defecto (`:0`, el Xorg del greeter de SDDM), que sí exige cookie → falla la autenticación y después se queda sin display. |

En Wayland no hay un Xorg de sesión: el único display X es el **Xwayland** que
levanta Hyprland (normalmente `:1`, pero el número puede cambiar). Hay que
pasarle ese display explícitamente con `-c`.

## Solución instalada

Todo lo aplica `nvidia/install-nvidia-fan.sh` (idempotente), que corre
opcionalmente desde `install.sh` si detecta una GPU NVIDIA con `nvidia-smi`:

1. Copia `nvidia/nvidia-fan-curve.sh` a `/usr/local/sbin/nvidia-fan-curve.sh`
   (`root:root`, 755).
2. Crea `/etc/sudoers.d/nvidia-fan-curve`:

   ```
   <usuario> ALL=(root) NOPASSWD: /usr/local/sbin/nvidia-fan-curve.sh
   ```

   Solo habilita **ese** script, que es de root y el usuario no puede editar,
   así que no equivale a `NOPASSWD: ALL`.
3. Hyprland lo arranca en cada login (`hypr/.config/hypr/hyprland.lua`):
   `pkill` del proceso viejo y `sudo -n` del script en background. `-n` evita
   que sudo intente pedir contraseña en un login sin terminal.

El script detecta el display de Xwayland solo (por la línea de comandos del
proceso `Xwayland`), aplica la curva cada 5 s y, al salir (logout, Ctrl+C,
`pkill`), devuelve el control al firmware con `GPUFanControlState=0`.

## Curva

| Temp GPU | Fan |
|----------|-----|
| ≤ 49 °C  | 30 % |
| ≤ 59 °C  | 42 % |
| ≤ 69 °C  | 55 % |
| ≤ 77 °C  | 70 % |
| ≤ 84 °C  | 85 % |
| > 84 °C  | 100 % |

Al **bajar** de escalón se exigen 3 °C de margen (histéresis) para que el fan
no oscile cuando la temperatura queda justo en un umbral. El mínimo es 30 %:
más silencioso que eso no compensa en una GTX 1070 (Pascal) y evita el
vaivén de los modos "zero fan".

## Uso

```bash
# Aplicar un solo ajuste (debug)
sudo /usr/local/sbin/nvidia-fan-curve.sh --once

# Ver display, temperatura, estado del control y % del fan (no necesita root)
/usr/local/sbin/nvidia-fan-curve.sh --status

# Arrancar el loop a mano (lo normal es que lo haga Hyprland)
sudo /usr/local/sbin/nvidia-fan-curve.sh &

# Devolver el control al firmware
sudo /usr/local/sbin/nvidia-fan-curve.sh --reset
```

Variables útiles: `NVIDIA_FAN_DISPLAY`, `NVIDIA_FAN_INTERVAL`,
`NVIDIA_FAN_GPU`, `NVIDIA_FAN_FORCE`.

## Verificación

```bash
nvidia-settings -q fans                                  # ¿cuántos fans ve el driver?
nvidia-settings -q '[gpu:0]/GPUFanControlState'          # 1 = curva propia, 0 = firmware
nvidia-settings -q '[fan:0]/GPUTargetFanSpeed'           # % objetivo
nvidia-smi --query-gpu=temperature.gpu,fan.speed --format=csv
```

## Troubleshooting

- **`no encontré un display X con NV-CONTROL`**: Hyprland no está corriendo, o
  Xwayland usa otro display. Probá `NVIDIA_FAN_DISPLAY=:1 ... --status`.
- **El ajuste falla con `Authorization required`**: este Xwayland sí exige
  cookie. Desde la sesión del usuario: `xhost +si:localuser:root` (paquete
  `xorg-xhost`) y reintentar. Es lo mismo que hacía falta a mano.
- **`nvidia-settings` no lista fans**: el driver no expone control de fan para
  esa GPU (pasa en muchos dGPU de laptop). No hay nada que hacer por esta vía.
- **Laptop**: el script se auto-omite (`chassis_type` 8/9/10/14) porque el fan
  lo maneja el EC del fabricante. En la Legion la curva correcta es la de
  `legion/` (`docs/legion/thermal.md`). Para forzar: `NVIDIA_FAN_FORCE=1`.

## Reversión

```bash
sudo /usr/local/sbin/nvidia-fan-curve.sh --reset
sudo rm -f /etc/sudoers.d/nvidia-fan-curve /usr/local/sbin/nvidia-fan-curve.sh
```

El autostart de `hyprland.lua` no molesta si el script no existe (`[ -x ... ]`).

## Alternativa con GUI

`gwe` (AUR: `yay -S gwe`) trae un helper de polkit y un editor de curva; hace
lo mismo sin mantener el script. La ventaja de este repo es que la curva queda
versionada y no depende de abrir una app.
