#!/bin/bash
# Curva de ventiladores custom para la Legion Pro 5 16ARX8 (EC chip 5507,
# BIOS familia LPCN).
#
# Limitación de firmware (ver docs/legion/thermal.md): en esta EC el método
# WMI solo permite escribir la VELOCIDAD (speed1/pwm1) de cada punto de la
# curva; las temperaturas umbral viven en el firmware y no son escribibles
# (temp/fan2/accel se leen como 0 por artefacto del protocolo WMI3). El
# control térmico fino se hace con el power mode (Fn+Q /
# /sys/firmware/acpi/platform_profile); este script fija la parte de speeds
# para que el escalado sea más progressivo que el stock.
#
# Valores en escala pwm 0-255. El EC los guarda como porcentaje de ~10000 RPM
# (pwm*100/255). Curva "fría" en %: 0, 20, 24, 34, 38, 44, 52, 62, 72, 82
# (los umbrales de temperatura son los de fábrica del EC, ~50 a ~90 °C): al
# no poder bajarse los umbrales (firmware), se sube el airflow de cada punto
# del escalón stock -> la temperatura de equilibrio baja (idle ~57-60 °C con
# 2400-3000 RPM, carga con escalado fuerte antes de los 90 °C). Contrapartida:
# más ruido en idle y posible vaivén suave cerca de los umbrales.
#
# Curva previa más silenciosa, por si se quiere volver: % 0,14,17,20,24,28,33,
# 38,45,50 -> pwm 0 36 44 51 62 72 85 97 115 127.
#
# El EC pierde esta curva al cambiar de power mode (Fn+Q) o al reiniciar:
# legion-fancurve.service la reaplica en cada boot. Re-aplicado manual:
#   sudo /usr/local/sbin/legion-fancurve.sh

set -e

# El índice de hwmon puede cambiar entre boots: se resuelve por nombre.
H="$(for d in /sys/devices/platform/legion/hwmon/hwmon*; do
        if [ "$(cat "$d/name" 2>/dev/null)" = legion_hwmon ]; then
            printf '%s' "$d"
            exit 0
        fi
    done
    exit 1)" || { echo "legion-fancurve: no encontré legion_hwmon (¿está cargado legion_laptop?)" >&2; exit 1; }

set -- 0 51 62 86 96 113 133 159 184 210
for i in 1 2 3 4 5 6 7 8 9 10; do
    printf '%s\n' "$1" > "$H/pwm1_auto_point${i}_pwm"
    shift
done

echo "legion-fancurve: curva aplicada (fan1=$(cat "$H/fan1_input") RPM, fan2=$(cat "$H/fan2_input") RPM)"
