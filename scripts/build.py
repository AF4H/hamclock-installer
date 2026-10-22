#!/usr/bin/env python3
"""Build a self-contained preseed and a repair script from the same stages."""
import base64
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGES = [
    ('configure', 'configure-target.sh'),
    ('wifi', 'install-wifi.sh'),  # Repair installer-media APT entries before downloads.
    ('install', 'install-hamclock.sh'),
    ('desktop', 'configure-desktop.sh'),
    ('mdns', 'install-mdns.sh'),
]

def target_command():
    commands = []
    temporary = []
    for name, filename in STAGES:
        payload = base64.b64encode((ROOT / 'scripts' / filename).read_bytes()).decode()
        target = f'/tmp/hamclock-{name}.sh'
        temporary.append(target)
        commands += [f'echo HamClock-stage={name}',
                     f'printf %s {payload} | base64 -d > {target}',
                     f'/bin/sh {target}']
    commands += ['rm ' + ' '.join(temporary), 'echo HamClock-stage=complete']
    # Preserve the failing stage's status, keep the full log on the target, and
    # expose a short tail in the Debian Installer syslog as well.
    return ('mkdir -p /var/log; status=0; { ' + ' && '.join(commands) +
            '; } >> /var/log/hamclock-installer.log 2>&1 || status=$?; '
            'tail -n 80 /var/log/hamclock-installer.log; exit "$status"')

def render():
    return (ROOT / 'preseed/base.cfg').read_text() + (
        "d-i preseed/late_command string in-target /bin/sh -c '" + target_command() + "'\n"
    )

def repair_script():
    return '#!/bin/sh\n# Run with sudo after finishing Debian installation.\n' + target_command() + '\n'

if __name__ == '__main__':
    output = ROOT / 'build'
    output.mkdir(exist_ok=True)
    (output / 'preseed.cfg').write_text(render())
    (output / 'repair-hamclock.sh').write_text(repair_script())
    print(output / 'preseed.cfg')
