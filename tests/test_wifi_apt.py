"""Regress the real bare-metal failure: active CD-ROM APT sources in late_command."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class AptTests(unittest.TestCase):
    def prepare(self, root):
        source = (ROOT / 'scripts/install-wifi.sh').read_text()
        program = re.search(r"<<'APT'\n(.*?)\nAPT", source, re.S).group(1)
        subprocess.run([sys.executable, '-', str(root)], input=program, text=True, check=True)

    def test_installer_media_disabled_and_firmware_not_duplicated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            apt = root / 'etc/apt'
            extra = apt / 'sources.list.d'
            extra.mkdir(parents=True)
            original = ('deb cdrom:[Debian 13 amd64 NETINST]/ trixie main non-free-firmware\n'
                        'deb https://deb.debian.org/debian trixie main non-free-firmware\n')
            (apt / 'sources.list').write_text(original)
            managed = extra / 'hamclock-firmware.sources'
            managed.write_text('Types: deb\nURIs: https://deb.debian.org/debian\nSuites: trixie\n'
                               'Components: non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n')
            self.prepare(root)
            text = (apt / 'sources.list').read_text()
            self.assertNotRegex(text, r'(?m)^deb cdrom:')
            self.assertIn('deb https://deb.debian.org/debian trixie main non-free-firmware\n', text)
            self.assertFalse(managed.exists())
            self.assertEqual((root / 'var/lib/hamclock-installer/apt-backup/sources.list').read_text(), original)
            self.prepare(root)
            self.assertEqual((apt / 'sources.list').read_text(), text)

    def test_deb822_media_and_network_stanzas_and_missing_firmware(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            extra = root / 'etc/apt/sources.list.d'
            extra.mkdir(parents=True)
            path = extra / 'debian.sources'
            path.write_text('Types: deb\nURIs: cdrom:[Debian13]/\nSuites: trixie\nComponents: main\n\n'
                            'Types: deb\nURIs: https://deb.debian.org/debian\nSuites: trixie\nComponents: main\n')
            self.prepare(root)
            stanzas = path.read_text().strip().split('\n\n')
            self.assertIn('Enabled: no', stanzas[0])
            self.assertNotIn('Enabled: no', stanzas[1])
            managed = extra / 'hamclock-firmware.sources'
            self.assertIn('Components: non-free-firmware', managed.read_text())
            first = path.read_text()
            self.prepare(root)
            self.assertEqual(path.read_text(), first)
