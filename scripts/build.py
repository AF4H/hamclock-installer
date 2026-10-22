#!/usr/bin/env python3
"""Build a self-contained preseed. No late-stage network script downloads."""
import base64
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def render():
    payload = base64.b64encode((ROOT / 'scripts/configure-target.sh').read_bytes()).decode()
    install_payload = base64.b64encode((ROOT / 'scripts/install-hamclock.sh').read_bytes()).decode()
    wifi_payload = base64.b64encode((ROOT / 'scripts/install-wifi.sh').read_bytes()).decode()
    desktop_payload = base64.b64encode((ROOT / 'scripts/configure-desktop.sh').read_bytes()).decode()
    return (ROOT / 'preseed/base.cfg').read_text() + (
        "d-i preseed/late_command string in-target /bin/sh -c '"
        f"printf %s {payload} | base64 -d > /tmp/hamclock-configure.sh && "
        "/bin/sh /tmp/hamclock-configure.sh && "
        f"printf %s {install_payload} | base64 -d > /tmp/hamclock-install.sh && "
        "/bin/sh /tmp/hamclock-install.sh && "
        f"printf %s {wifi_payload} | base64 -d > /tmp/hamclock-wifi.sh && "
        "/bin/sh /tmp/hamclock-wifi.sh && "
        f"printf %s {desktop_payload} | base64 -d > /tmp/hamclock-desktop.sh && "
        "/bin/sh /tmp/hamclock-desktop.sh && "
        "rm /tmp/hamclock-desktop.sh /tmp/hamclock-configure.sh /tmp/hamclock-install.sh /tmp/hamclock-wifi.sh'\n"
    )

if __name__ == '__main__':
    output = ROOT / 'build'
    output.mkdir(exist_ok=True)
    (output / 'preseed.cfg').write_text(render())
    print(output / 'preseed.cfg')
