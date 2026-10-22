#!/usr/bin/env python3
"""Build a self-contained preseed. No late-stage network script downloads."""
import base64
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def render():
    payload = base64.b64encode((ROOT / 'scripts/configure-target.sh').read_bytes()).decode()
    return (ROOT / 'preseed/base.cfg').read_text() + (
        "d-i preseed/late_command string in-target /bin/sh -c '"
        f"printf %s {payload} | base64 -d > /tmp/hamclock-configure.sh && "
        "/bin/sh /tmp/hamclock-configure.sh && rm /tmp/hamclock-configure.sh'\n"
    )

if __name__ == '__main__':
    output = ROOT / 'build'
    output.mkdir(exist_ok=True)
    (output / 'preseed.cfg').write_text(render())
    print(output / 'preseed.cfg')
