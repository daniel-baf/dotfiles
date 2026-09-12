#!/bin/bash
# ~/dotfiles/legion/install-legion-thermal.sh
#
# Stack térmico para la Legion Pro 5 16ARX8 (82WM, BIOS familia LPCN).
# Diagnóstico completo, limitaciones y cómo revertir: docs/legion/thermal.md.
#
# Qué hace (todo idempotente, se puede correr las veces que sea):
#   1. tlp (repo oficial) con política EPP/boost distinta para AC y batería.
#   2. LenovoLegionLinux por AUR (módulo DKMS legion_laptop + legion_cli):
#      telemetría real de fans/CPU/GPU y escritura de la curva del EC.
#   3. Blacklist de yogafan y lenovo_wmi_gamezone (conflicto con legion_laptop).
#   4. Curva de ventiladores custom + servicio systemd que la reaplica en
#      cada boot (el EC la pierde al cambiar power mode con Fn+Q).
#   5. nvme_core.default_ps_max_latency_us=250000 en el cmdline de Limine,
#      para que el NVMe Kingston NV2 (disco de sistema) entre en estados APST
#      de bajo consumo -- sin esto se queda caliente en idle.
#
# Al final hace falta REINICIAR para que activen el módulo DKMS, los
# blacklists y el cmdline nuevo.

set -u

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$DOTFILES_DIR/legion"

step()  { printf '==> %s\n' "$1"; }
warn()  { printf '    %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. TLP: EPP por AC/batería + boost off en batería
# ---------------------------------------------------------------------------
step "Instalando TLP..."
sudo pacman -S --needed --noconfirm tlp

# /etc/tlp.conf es de pacman (lo puede reescribir un upgrade): las directivas
# se ponen/actualizan de forma idempotente -- si la clave ya está activa se
# reemplaza, si no se agrega al final (en TLP gana la última definición).
set_tlp_kv() {
    local key="$1" val="$2"
    if sudo grep -qE "^${key}=" /etc/tlp.conf 2>/dev/null; then
        sudo sed -i "s|^${key}=.*|${key}=${val}|" /etc/tlp.conf
    else
        printf '%s=%s\n' "$key" "$val" | sudo tee -a /etc/tlp.conf >/dev/null
    fi
}

step "Configurando TLP (EPP balance_power en AC / power en batería, boost off en batería)..."
set_tlp_kv CPU_ENERGY_PERF_POLICY_ON_AC balance_power
set_tlp_kv CPU_ENERGY_PERF_POLICY_ON_BAT power
set_tlp_kv CPU_BOOST_ON_BAT 0
sudo systemctl enable --now tlp

# ---------------------------------------------------------------------------
# 2. LenovoLegionLinux (AUR): DKMS + legion_cli
# ---------------------------------------------------------------------------
step "Instalando dependencias de build del módulo DKMS..."
sudo pacman -S --needed --noconfirm dkms linux-headers

if command -v paru >/dev/null 2>&1; then
    step "Instalando LenovoLegionLinux (AUR: lenovolegionlinux-dkms-git + legion_cli)..."
    if ! paru -S --needed --noconfirm lenovolegionlinux-dkms-git lenovolegionlinux-git; then
        warn "Falló la instalación por AUR. Instalá a mano: paru -S lenovolegionlinux-dkms-git lenovolegionlinux-git"
        warn "(Sin el módulo, la curva custom y la telemetría real no funcionan, pero TLP y el APST del NVMe sí.)"
    fi
else
    warn "paru no está disponible todavía. Instalá a mano más tarde:"
    warn "    paru -S lenovolegionlinux-dkms-git lenovolegionlinux-git"
fi

# ---------------------------------------------------------------------------
# 3. Blacklists de módulos mainline conflictivos
# ---------------------------------------------------------------------------
step "Blacklisteando yogafan y lenovo_wmi_gamezone..."
sudo install -Dm644 "$SRC_DIR/blacklist-lenovo-mainline.conf" /etc/modprobe.d/blacklist-lenovo-mainline.conf

# ---------------------------------------------------------------------------
# 4. Curva de ventiladores + servicio de persistencia
# ---------------------------------------------------------------------------
step "Instalando curva de ventiladores custom + servicio systemd..."
sudo install -Dm755 "$SRC_DIR/legion-fancurve.sh" /usr/local/sbin/legion-fancurve.sh
sudo install -Dm644 "$SRC_DIR/legion-fancurve.service" /etc/systemd/system/legion-fancurve.service
sudo systemctl daemon-reload
sudo systemctl enable --now legion-fancurve.service

# ---------------------------------------------------------------------------
# 5. APST del NVMe (cmdline de Limine)
# ---------------------------------------------------------------------------
LIMINE_CONF=/boot/EFI/limine/limine.conf
if [ -f "$LIMINE_CONF" ]; then
    if grep -q 'nvme_core.default_ps_max_latency_us' "$LIMINE_CONF"; then
        step "APST del NVMe ya configurado en Limine."
    else
        step "Agregando nvme_core.default_ps_max_latency_us=250000 al cmdline de Limine..."
        sudo cp "$LIMINE_CONF" "$LIMINE_CONF.bak-dotfiles"
        sudo sed -i '/cmdline:/s/$/ nvme_core.default_ps_max_latency_us=250000/' "$LIMINE_CONF"
    fi
else
    warn "No encontré $LIMINE_CONF: revisá el cmdline a mano si cambiás de bootloader."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
step "Listo. Reiniciá para activar el módulo DKMS + blacklists + cmdline."
echo "    Verificación post-reboot:"
echo "      sensors | grep -A6 legion_hwmon     # RPM real de fans"
echo "      sudo cat /sys/kernel/debug/legion/fancurve | tail -12"
echo "    Detalles y reversión: docs/legion/thermal.md"
