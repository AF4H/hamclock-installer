#!/bin/sh
# Seed the pinned HamClock's first-run settings; never replace station data.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
mkdir -p /usr/local/bin
cat > /usr/local/bin/hamclock-defaults <<'DEFAULTS'
#!/usr/bin/python3
"""Initialize only an absent EEPROM for the pinned 4.27 amd64 binary."""
import os
from pathlib import Path
import struct

BINARY_ARCHIVE_SHA = '149c5cab1c4620afda7e3ad2e7e94a8d656b97bc613c96f01450e6f9f316bc06'


def initialize(home, state):
    destination = home / '.hamclock/eeprom'
    if destination.exists() or (home / '.rpihamclock_eeprom').exists():
        return 'Existing HamClock station settings preserved'
    if (state / 'hamclock-archive.sha256').read_text().strip() != BINARY_ARCHIVE_SHA:
        raise RuntimeError('Default EEPROM layout requires the pinned HamClock 4.27 binary')
    # NV_BASE=55, NV_COOKIE=0x5A. Offsets/lengths verified against the pinned
    # source's nvramsize.h + nvramlen.h. amd64 floats are little-endian IEEE754.
    entries = {94: struct.pack('<f', 33.919), 99: struct.pack('<f', -83.998),
               239: b'N0CALL'.ljust(12, b'\0'), 534: b'EM83aw\0'}
    memory = {}
    for address, value in entries.items():
        memory[address] = 0x5A
        memory.update({address + 1 + index: byte for index, byte in enumerate(value)})
    content = ''.join(f'{address:08X} {byte:02X}\n' for address, byte in sorted(memory.items()))
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return 'Existing HamClock station settings preserved'
    with os.fdopen(fd, 'w') as stream:
        stream.write(content)
    return 'First-run defaults saved: N0CALL, 33.919 N, 83.998 W (EM83aw)'


if __name__ == '__main__':
    print(initialize(Path.home(), Path('/var/lib/hamclock-installer')))
DEFAULTS
chmod 755 /usr/local/bin/hamclock-defaults
runuser -u hamclock -- /usr/local/bin/hamclock-defaults
