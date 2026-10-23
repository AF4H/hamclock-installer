#!/bin/sh
# Save requested Wi-Fi fallbacks without interrupting a working connection.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
python3 - "${HAMCLOCK_TEST_ROOT:-/}" <<'PRESETS'
import configparser
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

root = Path(sys.argv[1])
directory = root / 'etc/NetworkManager/system-connections'
directory.mkdir(parents=True, exist_ok=True, mode=0o700)
plans = {}
for ssid, priority in [('AF4H', 100), ('FieldLink', 50)]:
    matches = []
    for path in sorted(directory.iterdir()):
        if not path.is_file() or path.name.startswith('.') or path.name.endswith(('~', '.bak')):
            continue
        settings = configparser.ConfigParser(interpolation=None)
        settings.read(path)
        wifi = 'wifi' if settings.has_section('wifi') else '802-11-wireless'
        stored_ssid = settings.get(wifi, 'ssid', fallback='')
        if re.fullmatch(r'(?:[0-9]{1,3};)+', stored_ssid):
            try:
                stored_ssid = bytes(int(value) for value in stored_ssid.rstrip(';').split(';')).decode('utf-8')
            except (ValueError, UnicodeDecodeError):
                continue
        if stored_ssid == ssid and settings.get(wifi, 'mode', fallback='infrastructure') == 'infrastructure':
            matches.append(path)
    if not matches:
        identity = str(uuid.uuid5(uuid.NAMESPACE_DNS, 'hamclock-preset:' + ssid))
        path = directory / f'hamclock-preset-{identity}.nmconnection'
        if path.exists():
            raise SystemExit('An existing preset filename was customized; profiles retained')
        command = ['nmcli', '--offline', 'connection', 'add', 'type', 'wifi',
                   'con-name', ssid, 'connection.uuid', identity, 'ssid', ssid,
                   'wifi.mode', 'infrastructure', 'ipv4.method', 'auto', 'ipv6.method', 'auto',
                   'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', 'h@mradio']
        matches = [path]
    else:
        command = ['nmcli', '--offline', 'connection', 'modify']
    for path in matches:
        arguments = command + ['connection.autoconnect', 'yes', 'connection.autoconnect-priority', str(priority)]
        if path.exists() and ssid == 'FieldLink':
            arguments += ['wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', 'h@mradio']
        result = subprocess.run(arguments, input=path.read_text() if path.exists() else None,
                                capture_output=True, text=True)
        if result.returncode:
            raise SystemExit('NetworkManager rejected a preset; existing profiles retained')
        plans[path] = result.stdout
# Serialize every profile successfully before replacing any existing file.
for path, content in plans.items():
    if path.exists() and path.read_text() == content:
        path.chmod(0o600)
        continue
    fd, temporary = tempfile.mkstemp(prefix='.hamclock-preset-', dir=directory)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
print('Saved Wi-Fi preferences: AF4H priority 100; FieldLink priority 50')
PRESETS
mkdir -p /usr/local/sbin /etc/systemd/system/comitup.service.d
cat > /usr/local/sbin/hamclock-comitup <<'COMITUP'
#!/usr/bin/python3
"""Make Comitup honor saved NetworkManager autoconnect priorities."""
import sys


def prioritize(candidates, priorities):
    return sorted(candidates, key=lambda ssid: -priorities.get(ssid, 0))


def main():
    sys.path.insert(0, '/usr/share/comitup')
    from comitup import nm
    original = nm.get_candidate_connections

    def ordered(device):
        priorities = {}
        for connection in nm.get_all_connections():
            ssid = nm.get_ssid_from_connection(connection)
            if ssid:
                settings = connection.GetSettings()
                priority = int(settings.get('connection', {}).get('autoconnect-priority', 0))
                priorities[ssid] = max(priority, priorities.get(ssid, priority))
        return prioritize(original(device), priorities)

    nm.get_candidate_connections = ordered
    from comitup.comitup import main as run
    return run()


if __name__ == '__main__':
    sys.exit(main())
COMITUP
chmod 755 /usr/local/sbin/hamclock-comitup
cat > /etc/systemd/system/comitup.service.d/priorities.conf <<'CONF'
[Service]
ExecStart=
ExecStart=/usr/local/sbin/hamclock-comitup
CONF
systemctl daemon-reload
if systemctl is-active --quiet NetworkManager.service; then
    nmcli connection reload
    # Include live in-memory/generated profiles that have no /etc keyfile yet.
    nmcli -g UUID connection show | while IFS= read -r identity; do
        ssid=$(nmcli -g 802-11-wireless.ssid connection show "$identity" 2>/dev/null || true)
        case "$ssid" in
            AF4H) nmcli connection modify "$identity" connection.autoconnect yes connection.autoconnect-priority 100 ;;
            FieldLink) nmcli connection modify "$identity" connection.autoconnect yes connection.autoconnect-priority 50 wifi-sec.key-mgmt wpa-psk wifi-sec.psk 'h@mradio' ;;
        esac
    done
fi
echo 'Comitup priority ordering applies at its next start; no network service was restarted.'
