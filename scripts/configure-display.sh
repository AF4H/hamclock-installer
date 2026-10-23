#!/bin/sh
# Install an X11 display fitter; executed in the graphical user's environment.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
mkdir -p /usr/local/bin
cat > /usr/local/bin/hamclock-display <<'DISPLAY'
#!/usr/bin/python3
"""Fit the fixed 800x480 HamClock canvas on one active X11 output."""
import math
import os
import re
import subprocess


def plan(query):
    active = []
    output = None
    for line in query.splitlines():
        header = re.match(r'^(\S+) connected(?: primary)? (\d+)x(\d+)\+', line)
        if header:
            output = header[1]
        elif line and not line[0].isspace():
            output = None
        elif output:
            mode = re.match(r'^\s+(\d+)x(\d+)\s+.*\*', line)
            if mode:
                active.append((output, int(mode[1]), int(mode[2])))
    if len(active) != 1:
        return None
    name, width, height = active[0]
    scale = min(width / 800, height / 480)
    logical = (math.ceil(width / scale), math.ceil(height / scale))
    return name, width, height, logical


def main(run=subprocess.run):
    if not os.environ.get('DISPLAY'):
        print('Display fit skipped: no X11 display')
        return
    try:
        result = run(['xrandr', '--current'], capture_output=True, text=True, check=True, timeout=10)
        selected = plan(result.stdout)
        if not selected:
            print('Display fit skipped: requires one active output with a known mode')
            return
        name, width, height, (logical_width, logical_height) = selected
        logical = f'{logical_width}x{logical_height}'
        print(f'Display fit: {name} {width}x{height}, logical {logical}, HamClock 800x480', flush=True)
        run(['xrandr', '--output', name, '--pos', '0x0', '--scale-from', logical,
             '--panning', '0x0', '--fb', logical], check=True, timeout=15)
    except (OSError, subprocess.SubprocessError) as error:
        print(f'Display fit unavailable; keeping ordinary fullscreen: {error}', flush=True)
        # Restore an unscaled output after a partially applied transformation.
        if 'selected' in locals() and selected:
            name, width, height, _ = selected
            try:
                run(['xrandr', '--output', name, '--scale', '1x1', '--panning', '0x0',
                     '--fb', f'{width}x{height}'], check=True, timeout=15)
            except (OSError, subprocess.SubprocessError):
                pass


if __name__ == '__main__':
    main()
DISPLAY
chmod 755 /usr/local/bin/hamclock-display
echo 'Automatic single-display fullscreen fitting installed.'
