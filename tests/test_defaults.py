"""First-run EEPROM seeds must preserve any existing station data."""
from pathlib import Path
import re
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
source = re.search(r"<<'DEFAULTS'\n(.*?)\nDEFAULTS", (ROOT/'scripts/configure-defaults.sh').read_text(), re.S)[1]
module = {'__name__': 'defaults_test'}
exec(compile(source, 'defaults', 'exec'), module)


class DefaultsTests(unittest.TestCase):
    def fixture(self, root):
        home, state = root/'home', root/'state'
        home.mkdir(); state.mkdir()
        (state/'hamclock-archive.sha256').write_text(module['BINARY_ARCHIVE_SHA'])
        return home, state

    def test_new_station_coordinates_callsign_and_private_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, state = self.fixture(Path(tmp))
            module['initialize'](home, state)
            path = home/'.hamclock/eeprom'
            cells = {int(a,16): int(b,16) for a,b in (line.split() for line in path.read_text().splitlines())}
            def value(address, length):
                self.assertEqual(cells[address], 0x5A)
                return bytes(cells[address+i+1] for i in range(length))
            self.assertAlmostEqual(struct.unpack('<f', value(94,4))[0], 33.919, places=4)
            self.assertAlmostEqual(struct.unpack('<f', value(99,4))[0], -83.998, places=4)
            self.assertEqual(value(239,12).rstrip(b'\0'), b'N0CALL')
            self.assertEqual(value(534,7), b'EM83aw\0')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            original = path.read_bytes()
            module['initialize'](home,state)
            self.assertEqual(path.read_bytes(), original)

    def test_existing_and_legacy_stations_are_preserved(self):
        for name in ['.hamclock/eeprom', '.rpihamclock_eeprom']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                home,state = self.fixture(Path(tmp))
                path=home/name; path.parent.mkdir(exist_ok=True)
                path.write_text('operator settings')
                module['initialize'](home,state)
                self.assertEqual(path.read_text(), 'operator settings')
                if name.startswith('.rpihamclock'):
                    self.assertFalse((home/'.hamclock/eeprom').exists())

    def test_different_binary_is_rejected_without_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            home,state = self.fixture(Path(tmp))
            (state/'hamclock-archive.sha256').write_text('unknown')
            with self.assertRaises(RuntimeError):
                module['initialize'](home,state)
            self.assertFalse((home/'.hamclock/eeprom').exists())
