"""Disk consent must fail closed, exclude USB/media, and authorize exactly one disk."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DiskTests(unittest.TestCase):
    def fixture(self, tmp):
        root = Path(tmp)
        (root / 'proc').mkdir()
        (root / 'proc/mounts').write_text('')
        (root / 'sys/block').mkdir(parents=True)
        (root / 'bin').mkdir()
        (root / 'debconf').write_text('''db_subst() { echo "subst $*" >> "$HAMCLOCK_TEST_ROOT/calls"; }
db_fset() { :; }
db_input() { echo "input $*" >> "$HAMCLOCK_TEST_ROOT/calls"; }
db_go() { :; }
db_get() { RET=$TEST_CONSENT; }
db_set() { echo "set $*" >> "$HAMCLOCK_TEST_ROOT/calls"; }
''')
        for name in ['debconf-loadtemplate', 'poweroff', 'logger']:
            path = root / 'bin' / name
            path.write_text('#!/bin/sh\necho "'+name+' $*" >> "$HAMCLOCK_TEST_ROOT/calls"\n')
            path.chmod(0o755)
        return root

    def disk(self, root, name, usb=False, removable='0', sectors='41943040'):
        block = root / 'sys/block' / name
        block.mkdir()
        for filename, value in [('removable', removable), ('ro', '0'), ('size', sectors)]:
            (block / filename).write_text(value)
        device = root / 'sys/devices' / ('usb1' if usb else 'pci') / name
        device.mkdir(parents=True)
        (device / 'model').write_text('Fixture Disk')
        (device / 'serial').write_text(name+'-serial')
        (block / 'device').symlink_to(device)

    def run_script(self, root, consent):
        env = dict(os.environ, HAMCLOCK_TEST_ROOT=str(root), HAMCLOCK_DEBCONF=str(root/'debconf'),
                   TEST_CONSENT=consent, PATH=str(root/'bin')+':'+os.environ['PATH'])
        result = subprocess.run(['sh', str(ROOT/'scripts/installer-disk.sh')], env=env, capture_output=True, text=True)
        return result, (root/'calls').read_text()

    def test_explicit_consent_excludes_nonremovable_usb_and_sets_boot_disk(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.fixture(tmp)
            self.disk(root, 'vda')
            self.disk(root, 'sda', usb=True)
            result, calls = self.run_script(root, 'true')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('set partman-auto/disk /dev/vda', calls)
            self.assertIn('set grub-installer/bootdev /dev/vda', calls)
            self.assertNotIn('set partman-auto/disk /dev/sda', calls)
            self.run_script(root, 'false')  # Reentry reuses this boot's consent for this exact disk.
            self.assertEqual((root/'calls').read_text().count('input critical hamclock/erase-disk'), 1)

    def test_changed_disk_identity_requires_new_consent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.fixture(tmp)
            self.disk(root, 'vda')
            self.assertEqual(self.run_script(root, 'true')[0].returncode, 0)
            (root/'sys/block/vda/device/serial').write_text('replacement-disk')
            result, calls = self.run_script(root, 'false')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls.count('input critical hamclock/erase-disk'), 2)
            self.assertEqual(calls.count('set partman-auto/disk'), 1)

    def test_decline_does_not_authorize_disk(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.fixture(tmp)
            self.disk(root, 'vda')
            result, calls = self.run_script(root, 'false')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('poweroff', calls)
            self.assertNotIn('set partman-auto/disk', calls)
            self.assertFalse((root/'tmp/hamclock-disk-consent').exists())

    def test_two_internal_disks_stop_without_default_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.fixture(tmp)
            self.disk(root, 'vda'); self.disk(root, 'vdb')
            result, calls = self.run_script(root, 'true')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('found 2', calls)
            self.assertNotIn('set partman-auto/disk', calls)

    def test_installer_media_is_not_an_install_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.fixture(tmp)
            self.disk(root, 'sda'); self.disk(root, 'nvme0n1')
            (root/'proc/mounts').write_text('/dev/sda1 /cdrom iso9660 ro 0 0\n')
            result, calls = self.run_script(root, 'true')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('set partman-auto/disk /dev/nvme0n1', calls)

    def test_decimal_4gb_boundary_and_uefi_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.fixture(tmp)
            self.disk(root, 'vda', sectors='7812499')
            self.assertNotEqual(self.run_script(root, 'true')[0].returncode, 0)
            (root/'sys/block/vda/size').write_text('7812500')
            (root/'sys/firmware/efi').mkdir(parents=True)
            result, calls = self.run_script(root, 'true')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('method{ efi }', calls)
            self.assertIn('256 256 256 linux-swap', calls)
            self.assertIn('set partman-auto/disk /dev/vda', calls)

    def test_8gb_bios_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.fixture(tmp)
            self.disk(root, 'vda', sectors='15625000')
            result, calls = self.run_script(root, 'true')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('method{ biosgrub }', calls)
            self.assertNotIn('method{ efi }', calls)
