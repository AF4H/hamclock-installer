import base64
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build import render

class ProfileTests(unittest.TestCase):
    def test_preseed_and_embedded_script(self):
        seed = render()
        subprocess.run(['debconf-set-selections', '--checkonly'], input=seed, text=True, check=True)
        self.assertFalse(re.search(r'^\S+ (?:partman[^ ]*|grub-installer/bootdev) ', seed, re.M))
        payload = seed.split('printf %s ')[1].split(' |')[0]
        self.assertEqual(base64.b64decode(payload), (ROOT / 'scripts/configure-target.sh').read_bytes())
        installer_payload = seed.split('printf %s ')[2].split(' |')[0]
        self.assertEqual(base64.b64decode(installer_payload), (ROOT / 'scripts/install-hamclock.sh').read_bytes())
        subprocess.run(['sh', '-n'], input=base64.b64decode(installer_payload), check=True)
        subprocess.run(['sh', '-n'], input=base64.b64decode(payload), check=True)
        wifi_payload = seed.split('printf %s ')[3].split(' |')[0]
        self.assertEqual(base64.b64decode(wifi_payload), (ROOT / 'scripts/install-wifi.sh').read_bytes())
        subprocess.run(['sh', '-n'], input=base64.b64decode(wifi_payload), check=True)
        self.assertIn('priority=high', (ROOT / 'boot/hamclock.ipxe').read_text())
        self.assertNotIn('priority=critical', (ROOT / 'boot/hamclock.ipxe').read_text())

    def test_target_hostname_persists_and_services_configure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for directory in ['etc', 'usr/share/xsessions', 'bin']:
                (root / directory).mkdir(parents=True, exist_ok=True)
            (root / 'etc/hosts').write_text('127.0.0.1 localhost\n127.0.1.1 old\n::1 localhost ip6-localhost\n')
            (root / 'usr/share/xsessions/xfce.desktop').touch()
            for command in ['usermod', 'visudo', 'ssh-keygen', 'sshd', 'systemctl']:
                path = root / 'bin' / command
                path.write_text('#!/bin/sh\nprintf "%s\\n" "'+command+' $*" >> "$HAMCLOCK_TEST_ROOT/calls"\n')
                path.chmod(0o755)
            env = dict(os.environ, HAMCLOCK_TEST_ROOT=tmp, PATH=str(root / 'bin')+':'+os.environ['PATH'])
            def configure():
                return subprocess.run(['sh', str(ROOT / 'scripts/configure-target.sh')], env=env, capture_output=True)
            self.assertEqual(configure().returncode, 0)
            first = (root / 'etc/hostname').read_text()
            self.assertRegex(first, r'^hamclock-[0-9a-f]{5}\n$')
            self.assertEqual(configure().returncode, 0)
            self.assertEqual((root / 'etc/hostname').read_text(), first)
            hosts = (root / 'etc/hosts').read_text()
            self.assertEqual(hosts.count('127.0.1.1'), 1)
            self.assertIn('::1 localhost ip6-localhost', hosts)
            self.assertIn('usermod -aG sudo hamclock', (root / 'calls').read_text())
            self.assertIn('autologin-session=xfce', (root / 'etc/lightdm/lightdm.conf.d/50-hamclock.conf').read_text())
            (root / 'var/lib/hamclock-installer/hostname').write_text('invalid')
            self.assertNotEqual(configure().returncode, 0)
            self.assertEqual((root / 'etc/hostname').read_text(), first)

if __name__ == '__main__':
    unittest.main()
