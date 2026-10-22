"""Compile and exercise the real build-time elapsed-clock replacement."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ClockTests(unittest.TestCase):
    def test_monotonic_elapsed_and_uint32_wrap(self):
        installer = (ROOT / 'scripts/install-hamclock.sh').read_text()
        patcher = re.search(r"<<'MONOTONIC'\n(.*?)\nMONOTONIC", installer, re.S).group(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'clock.cpp'
            source.write_text('''uint32_t millis(void)
{
    struct timeval t;
    gettimeofday(&t, nullptr);
    return 0;
}
''')
            subprocess.run([sys.executable, '-', str(source)], input=patcher, text=True, check=True)
            harness = '''#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <ctime>
static timespec current_time;
static int fake_clock_gettime(clockid_t clock, timespec *out) {
    assert(clock == CLOCK_MONOTONIC);
    *out = current_time;
    return 0;
}
#define clock_gettime fake_clock_gettime
'''
            main = '''
#undef clock_gettime
static void advance(uint64_t milliseconds) {
    uint64_t ns = 900000000ULL + milliseconds * 1000000ULL;
    current_time.tv_sec = 100 + ns / 1000000000ULL;
    current_time.tv_nsec = ns % 1000000000ULL;
}
int main() {
    advance(0); assert(millis() == 0);
    advance(200); assert(millis() == 200);
    advance(500); assert(millis() == 500);
    advance((1ULL << 32) + 17); assert(millis() == 17);
}
'''
            source.write_text(harness + source.read_text() + main)
            executable = root / 'check-clock'
            subprocess.run(['g++', '-std=c++17', '-Wall', '-Werror', str(source), '-o', str(executable)], check=True)
            subprocess.run([str(executable)], check=True)
