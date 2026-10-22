import base64
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build import render, repair_script, STAGES, target_command

class ProfileTests(unittest.TestCase):
    def test_preseed_and_embedded_script(self):
        seed = render()
        subprocess.run(['debconf-set-selections', '--checkonly'], input=seed, text=True, check=True)
        self.assertFalse(re.search(r'^\S+ (?:partman[^ ]*|grub-installer/bootdev) ', seed, re.M))
        payloads = re.findall(r'printf %s ([A-Za-z0-9+/=]+) \| base64 -d', seed)
        self.assertEqual(len(payloads), len(STAGES))
        for encoded, (_, filename) in zip(payloads, STAGES):
            payload = base64.b64decode(encoded)
            self.assertEqual(payload, (ROOT / 'scripts' / filename).read_bytes())
            subprocess.run(['sh', '-n'], input=payload, check=True)
        subprocess.run(['sh', '-n'], input=repair_script(), text=True, check=True)
        self.assertLess(seed.index('HamClock-stage=wifi'), seed.index('HamClock-stage=install'))
        self.assertIn('apt-setup/disable-cdrom-entries boolean true', seed)
        self.assertIn('priority=high', (ROOT / 'boot/hamclock.ipxe').read_text())
        self.assertNotIn('priority=critical', (ROOT / 'boot/hamclock.ipxe').read_text())

    def test_stage_failure_keeps_status_and_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'scripts').mkdir()
            (root / 'scripts/fail.sh').write_text('echo stage-diagnostic\nexit 23\n')
            (root / 'scripts/after.sh').write_text('echo SHOULD_NOT_RUN\n')
            with patch('build.ROOT', root), patch('build.STAGES', [('fail', 'fail.sh'), ('after', 'after.sh')]):
                command = target_command().replace('/var/log', str(root / 'log')).replace('/tmp/hamclock-', str(root / 'stage-'))
            result = subprocess.run(['sh', '-c', command], text=True, capture_output=True)
            self.assertEqual(result.returncode, 23)
            self.assertIn('stage-diagnostic', result.stdout)
            log = (root / 'log/hamclock-installer.log').read_text()
            self.assertIn('HamClock-stage=fail', log)
            self.assertNotIn('SHOULD_NOT_RUN', log)

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
