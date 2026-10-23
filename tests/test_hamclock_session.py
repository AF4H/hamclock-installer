"""Exercise first-session startup when the user unit is not loaded yet."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SessionTests(unittest.TestCase):
    def test_fresh_and_failed_unit_start(self):
        source = (ROOT / 'scripts/install-hamclock.sh').read_text()
        session = re.search(r"<<'SESSION'\n(.*?)\nSESSION", source, re.S).group(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / 'session'
            launcher.write_text(session + '\n')
            systemctl = root / 'systemctl'
            systemctl.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CALL_LOG"
case "$*" in
  *is-failed*) [ "$UNIT_FAILED" = yes ] ;;
  *reset-failed*) [ "$UNIT_FAILED" = yes ] ;;
  *) exit 0 ;;
esac
''')
            systemctl.chmod(0o755)
            for failed in ['no', 'yes']:
                with self.subTest(failed=failed):
                    log = root / ('calls-' + failed)
                    env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
                               CALL_LOG=str(log), UNIT_FAILED=failed)
                    result = subprocess.run(['sh', str(launcher)], env=env, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    calls = log.read_text()
                    self.assertIn('--user import-environment DISPLAY XAUTHORITY', calls)
                    self.assertIn('--user start hamclock.service', calls)
                    self.assertEqual('--user reset-failed hamclock.service' in calls, failed == 'yes')
