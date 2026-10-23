"""Check aspect-preserving sizing and safe fallback without changing a display."""
import os
from pathlib import Path
import re
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
source = re.search(r"<<'DISPLAY'\n(.*?)\nDISPLAY", (ROOT/'scripts/configure-display.sh').read_text(), re.S)[1]
module = {'__name__': 'display_test'}
exec(compile(source, 'hamclock-display', 'exec'), module)


def query(width, height):
    return f'eDP-1 connected primary {width}x{height}+0+0\n   {width}x{height} 60.00*+\nHDMI-1 disconnected\n'


class DisplayTests(unittest.TestCase):
    def test_aspect_fit(self):
        for width, height, logical in [(1366, 768, (854, 480)), (1920, 1080, (854, 480)),
                                       (1280, 1024, (800, 640)), (800, 480, (800, 480)),
                                       (768, 1366, (800, 1423)), (640, 360, (854, 480))]:
            with self.subTest(size=(width, height)):
                self.assertEqual(module['plan'](query(width, height))[-1], logical)

    def test_multiple_outputs_are_not_reconfigured(self):
        self.assertIsNone(module['plan'](query(1366, 768)+'HDMI-2 connected 1920x1080+1366+0\n   1920x1080 60.00*\n'))
        self.assertIsNone(module['plan']('Screen 0: no outputs\n'))

    @patch.dict(os.environ, DISPLAY=':0')
    def test_transform_failure_rolls_back(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if len(calls) == 1:
                return subprocess.CompletedProcess(args, 0, stdout=query(1366, 768))
            if len(calls) == 2:
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0)
        module['main'](run)
        self.assertIn('854x480', calls[1])
        self.assertIn('1x1', calls[2])
        self.assertIn('1366x768', calls[2])
