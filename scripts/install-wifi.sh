#!/bin/sh
# Run inside the installed Debian 13 target; reboot after standalone upgrades.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
if [ "$ID" != debian ] || [ "$VERSION_ID" != 13 ]; then
    echo 'This Wi-Fi profile requires Debian 13' >&2; exit 1;
fi
state=/var/lib/hamclock-installer
mkdir -p "$state" /etc/apt/sources.list.d
exec 9>"$state/wifi-install.lock"
flock -n 9 || { echo 'Another Wi-Fi installation is running' >&2; exit 1; }
# A separate component also supports upgrades from the earlier base image.
cat > /etc/apt/sources.list.d/hamclock-firmware.sources <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie
Components: non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    network-manager comitup firmware-iwlwifi firmware-realtek firmware-atheros \
    firmware-brcm80211 firmware-mediatek firmware-libertas firmware-misc-nonfree
# XFCE's NetworkManager owns Wi-Fi; preserve existing wired and saved connections.
# Refuse a conflicting legacy Wi-Fi configuration rather than erase credentials
# or interrupt a live SSH upgrade. Fresh XFCE installs normally have loopback only.
python3 - <<'PY'
from pathlib import Path
import re
paths = [Path('/etc/network/interfaces')]
paths += list(Path('/etc/network/interfaces.d').glob('*'))
wifi = {p.name for p in Path('/sys/class/net').iterdir() if (p / 'wireless').exists()}
for path in paths:
    if not path.is_file():
        continue
    text = '\n'.join(line.split('#', 1)[0] for line in path.read_text().splitlines())
    interfaces = re.findall(r'^\s*iface\s+(\S+)', text, re.M)
    if re.search(r'^\s*(?:wpa-|wireless-)', text, re.M) or any(
        name in wifi or name.startswith(('wlan', 'wl')) for name in interfaces
    ):
        raise SystemExit(f'Move Wi-Fi configuration from {path} to NetworkManager before retrying')
PY
mkdir -p /etc/systemd/system/comitup.service.d
# Keep an Ethernet-only machine healthy. Reboot after adding a Wi-Fi adapter,
# or start Comitup manually once NetworkManager sees the new device.
cat > /etc/systemd/system/comitup.service.d/hamclock.conf <<'EOF'
[Unit]
Wants=NetworkManager.service
After=NetworkManager.service

[Service]
ExecCondition=/usr/sbin/comitup --check
EOF
# Preserve operator changes and Wi-Fi credentials on subsequent runs.
if [ ! -f "$state/wifi-configured" ]; then
    cp -p /etc/comitup.conf "$state/comitup.conf.before-hamclock"
    cat > /etc/comitup.conf <<'EOF'
# HamClock setup hotspot: connect with a phone, then open http://10.41.0.1
ap_name: <hostname>-setup
ap_password: h@mradio
enable_appliance_mode: false
enable_nuke: false
EOF
    chmod 600 /etc/comitup.conf
    touch "$state/wifi-configured"
fi
systemctl enable NetworkManager.service comitup.service
echo 'Wi-Fi setup installed. Reboot to activate; existing network configuration was preserved.'
