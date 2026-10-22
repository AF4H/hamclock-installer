"""Exercise remaster orchestration with read-only extracted menu fixtures."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class UsbBuilderTests(unittest.TestCase):
    def test_read_only_menus_and_shared_preseed(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            iso = work / 'input.iso'
            iso.write_bytes(b'fixture ISO')
            output = work / 'output.iso'
            fake = work / 'xorriso'
            fake.write_text('''#!/usr/bin/env python3
import sys
from pathlib import Path
args = sys.argv[1:]
if '-extract' in args:
    destination = Path(args[-1])
    destination.write_text('# original menu\\n')
    destination.chmod(0o444)
else:
    for index, arg in enumerate(args):
        if arg == '-map':
            source, target = args[index+1:index+3]
            text = Path(source).read_text()
            if target.endswith('.cfg') and target != '/preseed.cfg':
                assert '# original menu' not in text
                assert 'timeout 0' in text or 'set timeout=0' in text
                assert 'vesamenu' not in text
                assert 'netcfg/wireless_essid=AF4H' in text
                assert 'priority=high' in text
                assert 'preseed/file=/cdrom/preseed.cfg' in text
            else:
                assert 'preseed/late_command' in text
    Path(args[args.index('-outdev')+1]).write_bytes(b'remastered fixture')
''')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=str(work) + ':' + os.environ['PATH'])
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/build-usb.py'),
                str(iso), hashlib.sha256(iso.read_bytes()).hexdigest(), str(output)],
                env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.exists())
