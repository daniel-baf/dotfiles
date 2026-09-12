# Térmica de la Legion Pro 5 16ARX8 en Linux

> Diagnóstico y solución del problema original: *"la laptop se calienta con el
> cargador conectado y los ventiladores no arrancan"* (en Windows, con Lenovo
> Vantage, todo funcionaba bien).

## Síntoma y diagnóstico (resumen)

Equipo: **Legion Pro 5 16ARX8** (82WM, BIOS `LPCN65WW`), Arch Linux, AMD
Ryzen 7745HX + RTX 4060, kernel 6.x+. El disco de sistema en Linux es el
**Kingston NV2** (`nvme1`); Windows arranca del SKHynix (`nvme0`).

Hallazgos de la investigación:

| # | Hallazgo | Evidencia |
|---|----------|-----------|
| 1 | Telemetría de fans rota: el driver mainline `yogafan` reportaba **0 RPM falso** siempre | `sensors` con fans a 0 mientras giraban a 2100 RPM (audibles) |
| 2 | Curva de ventiladores del EC poco agresiva en `balanced` + nada que reaccionara al conectar el cargador | CPU a 60 °C en idle con fans apagados; stress liviano escalaba a 100 °C antes de que movieran una aspa |
| 3 | **Carga rápida de ~50 W** bajo el trackpad hasta el 80% al conectar el cargador | `BAT0 power1 ≈ 51 W` con `capacity 50%` — calor en la zona del trackpad en uso liviano |
| 4 | NVMe Kingston NV2 **sin APST efectivo**: sensor interno a 76.9 °C en idle | `nvme smart-log /dev/nvme1` → Sensor 2: 77 °C (composite 51 °C); `default_ps_max_latency_us=100000` limitaba los power states |
| 5 | Sin daemon de energía activo (ni TLP, ni power-profiles-daemon) | `platform_profile` fijo, EPP sin cambiar entre AC/batería |

La batería ya tiene `charge_types = Long_Life` (tope 80%, persiste en el EC
desde Vantage): la carga corta al 80% y el calor de la zona del trackpad
desaparece.

## Solución instalada

Todo lo aplica `legion/install-legion-thermal.sh` (idempotente), que corre
opcionalmente desde `install.sh` si detecta la 16ARX8 por DMI:

1. **TLP** (repo oficial): `CPU_ENERGY_PERF_POLICY_ON_AC=balance_power`,
   `CPU_ENERGY_PERF_POLICY_ON_BAT=power`, `CPU_BOOST_ON_BAT=0`.
   Nota amd-pstate-epp: los valores válidos son los de
   `energy_performance_available_preferences`
   (`default performance balance_performance balance_power power custom`);
   `balance` a secas es de Intel/EPB y da `Invalid argument`.
2. **LenovoLegionLinux** (AUR: `lenovolegionlinux-dkms-git` +
   `lenovolegionlinux-git`): módulo `legion_laptop` que habla con el EC.
   Da telemetría real (`legion_hwmon`: RPM de ambos fans + temps CPU/GPU/IC) y
   escritura de la curva.
3. **Blacklist** de `yogafan` y `lenovo_wmi_gamezone`
   (`/etc/modprobe.d/blacklist-lenovo-mainline.conf`).
4. **Curva custom** (`/usr/local/sbin/legion-fancurve.sh` + servicio
   `legion-fancurve.service`): curva "fría" con speeds pwm
   `0 51 62 86 96 113 133 159 184 210`
   (≈ 0/20/24/34/38/44/52/62/72/82 % de ~10000 RPM). Como los umbrales de
   temperatura no son escribibles en esta EC, la estrategia es subir el
   airflow de cada punto del escalón stock: idle queda en ~57-60 °C con
   2400-3000 RPM y bajo carga los fans escalan fuerte antes de los 90 °C.
   La curva anterior, más silenciosa, queda documentada en el propio script.
5. **APST del NVMe**: `nvme_core.default_ps_max_latency_us=250000` en el
   cmdline de Limine (`/boot/EFI/limine/limine.conf`, backup `.bak-dotfiles`).

Requiere **un reinicio** después de instalar (DKMS + blacklists + cmdline).

## Limitación importante del firmware (EC 5507 / LPCN)

El acceso a la curva en este modelo es por WMI (`ACCESS_METHOD_WMI3`) y el
método **solo transmite la velocidad (`speed1`) de cada punto**
(`wmi_write_fancurve_custom` en `legion-laptop.c` manda un buffer con 10
bytes de speed). Consecuencias:

- Las **temperaturas umbral de la curva no son escribibles** (viven en el
  firmware). El escalado térmico fino se controla con el power mode: **Fn+Q**
  o `/sys/firmware/acpi/platform_profile` (`quiet`/`balanced`/`performance`/`custom`).
- En `sudo cat /sys/kernel/debug/legion/fancurve`, las columnas
  temp/fan2/accel se leen **en 0 por artefacto** del protocolo (la lectura
  WMI hace memset y solo llena speeds). El loop térmico real del EC está
  intacto y usa sus umbrales internos de fábrica.
- `legion_cli fancurve-write-file-to-hw` (y legiond) **fallan** en este
  modelo con `OSError: [Errno 95]` al intentar escribir `accel` — por eso la
  curva se aplica con el script de sysfs, que solo toca `pwm1_auto_pointN_pwm`.
- Escala: el hwmon toma pwm 0-255 y el EC lo guarda como **porcentaje**
  (`pwm*100/255`). Para lograr P% hay que escribir `P*255/100` (con redondeo
  hacia arriba si queda justo en el borde).

## Verificación

```bash
# Telemetría real (post-reboot, con legion_laptop cargado)
sensors | grep -A6 legion_hwmon
# Fans a ~60 °C deberían girar ~1700-2000 RPM, no 0.

# Curva cargada en el EC (speed1[u] = porcentaje)
sudo cat /sys/kernel/debug/legion/fancurve | grep -A12 'Current fan curve in hardware:$'

# APST del NVMe activo
grep . /sys/module/nvme_core/parameters/default_ps_max_latency_us   # 250000

# Batería: corta la carga al 80%
cat /sys/class/power_supply/BAT0/status    # "Not charging" al llegar
```

Stress test de referencia (`for i in 1 2 3 4; do timeout 90 yes >/dev/null & done`):
con la curva aplicada los fans escalan 2100→3700 RPM en ~15 s y el CPU
recupera 61 °C a los 40 s de cortar la carga. El **pico inicial de 97-100 °C
en los primeros segundos es inercial** (boost del 7745HX: descarga calor más
rápido de lo que cualquier fan físico responde) y se estabiliza con throttle.
Si molesta, la única palanca real es cap de PPT con `ryzenadj` (ver abajo).

## Uso en las piernas (calor del chasis por abajo)

Con cargador puesto, las fuentes de calor que se sienten abajo son, en orden:
la **carga rápida de la batería** (~52 W bajo el trackpad hasta llegar al
tope), el **CPU** con EPP `balance_performance` manteniendo boost alto en uso
liviano, y la **dGPU despierta** (~11 W, P4, por Hyprland/electron — mientras
el escritorio renderice en la NVIDIA no baja de ahí).

Mitigaciones aplicadas:
- EPP `balance_power` en AC (TLP) — boost menos ansioso en uso liviano.
- Curva con más airflow en la zona 60-70 °C (p4/p5).
- `legion_cli batteryconservation-enable`: congela la carga donde esté
  (tarda ~2 min en aplicar; luego oscila Charging/Discharging alrededor del
  nivel — normal en Lenovo). Con `disable` vuelve a cargar. Alternativa sin
  conservation: dejar que la carga llegue al tope (80% con Long_Life).
- El fondo de apps (electron ×2 + spotify + uvicorn ≈ 80% de un core) sostiene
  ~60-67 °C en idle: cerrar Spotify/electron en modo "piernas" baja un par de
  grados más.

## Mantenimiento

- **Fn+Q resetea la curva** (cambio de power mode): el servicio la reaplica
  solo en el boot. Re-aplicado manual inmediato:
  `sudo /usr/local/sbin/legion-fancurve.sh`
- **Update de kernel**: DKMS recompila solo. Si algún día el paquete `-git`
  no compila contra un kernel recién salido, la curva/telemetría dejan de
  funcionar hasta que actualicen el paquete — TLP y el APST siguen andando.
- El índice `hwmon5` puede cambiar entre boots; el script resuelve el path por
  nombre (`legion_hwmon`), no hardcodea el número.

## Advertencias del firmware (aprendidas por las malas)

- **NO usar `max-power` (platform_profile extreme)**: en BIOS LPCN65WW el EC
  **corta la energía instantáneamente** al recibir el modo (apagón duro, sin
  shutdown; journal corta seco en el mismo segundo del echo). Los perfiles
  seguros son `quiet`/`balanced`/`performance`/`custom`.
- Un corte de energía duro puede **resetear el modo de carga del EC**: de
  `Long_Life` (tope 80%) vuelve a `Fast` (carga rápida a 100%, ~88 W = calor
  bajo el trackpad de nuevo). Verificar y restaurar con:
  ```bash
  cat /sys/class/power_supply/BAT0/charge_types
  echo Long_Life | sudo tee /sys/class/power_supply/BAT0/charge_types
  ```
- El techo de ventiladores en `balanced` es ~3700 RPM: a plena carga el EC no
  pasa de ahí aunque la curva pida 70-80% (cap de firmware por power mode;
  en otros modelos LLL lo destraba con `fan_unlock`, no habilitado para LPCN).
  Consecuencia: los picos de boost (~97-100 °C) solo bajan capando PPT
  (ryzenadj).

## Cómo revertir todo

```bash
sudo systemctl disable --now legion-fancurve.service tlp
sudo rm /etc/systemd/system/legion-fancurve.service /usr/local/sbin/legion-fancurve.sh \
        /etc/modprobe.d/blacklist-lenovo-mainline.conf
sudo paru -R lenovolegionlinux-dkms-git lenovolegionlinux-git
# Limpiar las 3 directivas de /etc/tlp.conf (o desinstalar tlp) y sacar
# nvme_core.default_ps_max_latency_us del cmdline de Limine (hay backup
# .bak-dotfiles). La curva del EC vuelve a stock con Fn+Q o un reboot.
```

## Opcionales no instalados

- **ryzenadj** (AUR): cap de PPT/STAPM (p. ej. `--stapm-limit=45000`) para
  eliminar el pico de boost de ~97 °C a costa de un poco de performance.
- **BIOS**: chequear en el soporte de Lenovo (modelo 82WM) si hay algo más
  nuevo que `LPCN65WW` — las notas de LLL mencionan fixes térmicos en la
  familia LPCN.
- **Pad térmico M.2**: el sensor 2 del Kingston NV2 lee 76.9 °C fijos
  (sensor sintético atascado, ignorar); si el *composite* supera 70 °C bajo
  carga, un pad de $2 sobre el NV2 baja varios grados.
