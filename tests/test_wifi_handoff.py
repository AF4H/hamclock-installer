"""Migrate the DHCP/WPA stanzas left by Debian Installer without losing credentials."""
from pathlib import Path
import re
import stat
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = re.search(r"<<'MIGRATE'\n(.*?)\nMIGRATE", (ROOT / 'scripts/install-wifi.sh').read_text(), re.S).group(1)

class HandoffTests(unittest.TestCase):
    def migrate(self, root, failure=False):
        def offline(command, **kwargs):
            self.assertEqual(command[:5], ['nmcli', '--offline', 'connection', 'add', 'type'])
            self.assertTrue(kwargs['capture_output'])
            self.assertTrue(kwargs['text'])
            self.calls.append(command)
            # Unit-test the migration transaction separately from NM serialization.
            # The real offline command/profile are also exercised in a Debian VM.
            values = {command[i]: command[i + 1] for i in range(4, len(command), 2)}
            text = '[connection]\nuuid=' + values['connection.uuid'] + '\n[wifi]\nssid=' + values['ssid'] + '\n'
            text += '[wifi-security]\npsk=' + values.get('wifi-sec.psk', '') + '\n'
            return SimpleNamespace(returncode=1 if failure else 0, stdout=text)
        with patch.object(sys, 'argv', ['-', str(root)]), patch('subprocess.run', offline):
            exec(compile(PROGRAM, 'wifi-handoff', 'exec'), {'__name__': '__main__'})

    def setUp(self):
        self.calls = []

    def test_credentials_wired_settings_permissions_and_repeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            network = root / 'etc/network'
            network.mkdir(parents=True)
            connections = root / 'etc/NetworkManager/system-connections'
            connections.mkdir(parents=True)
            operator = connections / 'operator.nmconnection'
            operator.write_text('existing operator configuration')
            original = ('source /etc/network/interfaces.d/*\n'
                        'auto lo eth0 wlp2s0 # keep wired\niface lo inet loopback\n'
                        'iface eth0 inet static\n address 192.0.2.25/24\n pre-up echo one\n pre-up echo two\n'
                        'allow-hotplug wlp2s0\niface wlp2s0 inet dhcp\n'
                        ' wpa-ssid Test # Wi-Fi; network\n wpa-psk secret#password;123\n'
                        'iface wlp2s0 inet6 auto\n')
            path = network / 'interfaces'
            path.write_text(original)
            self.migrate(root)
            text = path.read_text()
            self.assertIn('auto lo eth0 # keep wired\n', text)
            self.assertIn('iface eth0 inet static\n address 192.0.2.25/24\n pre-up echo one\n pre-up echo two\n', text)
            self.assertNotIn('wlp2s0', text)
            self.assertNotIn('secret#password', text)
            files = list(connections.glob('hamclock-installer-*.nmconnection'))
            self.assertEqual(len(files), 1)
            self.assertIn('ssid=Test # Wi-Fi; network', files[0].read_text())
            self.assertIn('psk=secret#password;123', files[0].read_text())
            self.assertEqual(stat.S_IMODE(files[0].stat().st_mode), 0o600)
            backup = root / 'var/lib/hamclock-installer/network-backup'
            self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o700)
            self.assertEqual((backup / 'etc/network/interfaces').read_text(), original)
            self.assertEqual(stat.S_IMODE((backup / 'etc/network/interfaces').stat().st_mode), 0o600)
            self.migrate(root)
            self.assertEqual(path.read_text(), text)
            self.assertEqual(len(list(connections.glob('hamclock-installer-*.nmconnection'))), 1)
            self.assertEqual(operator.read_text(), 'existing operator configuration')
            self.assertEqual(len(self.calls), 1)

    def test_static_or_external_supplicant_config_is_preserved(self):
        for body in ['iface wlan0 inet static\n wpa-ssid Test\n wpa-psk secret123\n address 192.0.2.1\n',
                     'iface wlan0 inet dhcp\n wpa-conf /etc/wpa_supplicant.conf\n']:
            with self.subTest(body=body), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                path = root / 'etc/network/interfaces'
                path.parent.mkdir(parents=True)
                path.write_text(body)
                with self.assertRaisesRegex(SystemExit, 'Unsupported'):
                    self.migrate(root)
                self.assertEqual(path.read_text(), body)
                self.assertFalse((root / 'etc/NetworkManager/system-connections').exists())

    def test_rejected_profile_does_not_remove_legacy_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / 'etc/network/interfaces.d/wifi'
            path.parent.mkdir(parents=True)
            original = 'allow-hotplug radio0\niface radio0 inet dhcp\n wpa-ssid Test\n wpa-psk short\n'
            path.write_text(original)
            with self.assertRaisesRegex(SystemExit, 'originals retained') as error:
                self.migrate(root, failure=True)
            self.assertNotIn('short', str(error.exception))
            self.assertEqual(path.read_text(), original)
            self.assertFalse((root / 'etc/NetworkManager/system-connections').exists())
