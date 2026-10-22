#!/usr/bin/env python3
"""Remaster a verified Debian 13 amd64 netinst ISO; never writes a device."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile
import stat
from build import ROOT, render

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('iso', type=Path)
p.add_argument('sha256', help='Expected SHA256 from independently verified Debian SHA256SUMS')
p.add_argument('output', type=Path)
a = p.parse_args()
if a.output.exists() or a.output.resolve() == a.iso.resolve():
    p.error('output must be a new file')
with a.iso.open('rb') as source:
    digest = hashlib.file_digest(source, 'sha256').hexdigest()
if digest != a.sha256.lower():
    p.error('input ISO checksum mismatch')

def run(*args):
    subprocess.run(['xorriso', *map(str, args)], check=True)

with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    # These paths are from Debian amd64 netinst, not live or DVD images.
    for source, name in [('/isolinux/isolinux.cfg', 'isolinux.cfg'), ('/boot/grub/grub.cfg', 'grub.cfg')]:
        run('-osirrox', 'on', '-indev', a.iso, '-extract', source, temp / name)
        # Debian ISO menu files are read-only; extraction preserves their modes.
        menu = temp / name
        menu.chmod(menu.stat().st_mode | stat.S_IWUSR)
    args = ('auto=true priority=high interface=auto netcfg/disable_autoconfig=false '
            'netcfg/get_hostname=hamclock-install netcfg/get_domain=local '
            'netcfg/wireless_essid=AF4H netcfg/wireless_security_type=wpa '
            'netcfg/wireless_wpa=h@mradio preseed/file=/cdrom/preseed.cfg quiet')
    (temp / 'isolinux.cfg').write_text(
        'path \nprompt 0\ntimeout 0\ndefault hamclock\n'
        'label hamclock\n  kernel /install.amd/vmlinuz\n'
        '  append initrd=/install.amd/initrd.gz ' + args + ' ---\n')
    (temp / 'grub.cfg').write_text(
        'if loadfont $prefix/font.pf2; then\n'
        '  insmod all_video\n  insmod gfxterm\n  terminal_output gfxterm\nfi\n'
        'set default=0\nset timeout_style=hidden\nset timeout=0\n'
        'menuentry "HamClock automatic installation" {\n'
        '  linux /install.amd/vmlinuz ' + args + ' ---\n'
        '  initrd /install.amd/initrd.gz\n}\n')
    (temp / 'preseed.cfg').write_text(render())
    # Replay the original hybrid boot metadata; both firmware paths boot directly.
    run('-indev', a.iso, '-outdev', a.output, '-boot_image', 'any', 'replay',
        '-map', temp / 'isolinux.cfg', '/isolinux/isolinux.cfg',
        '-map', temp / 'grub.cfg', '/boot/grub/grub.cfg',
        '-map', temp / 'preseed.cfg', '/preseed.cfg')
print(a.output)
