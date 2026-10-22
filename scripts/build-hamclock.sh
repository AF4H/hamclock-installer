#!/bin/sh
# Build once on Debian 13 amd64, never on the installation target.
set -eu
output=${1:?Usage: build-hamclock.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
output=$(realpath "$output")
[ "$(dpkg --print-architecture)" = amd64 ] || { echo 'amd64 required' >&2; exit 1; }
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT HUP INT TERM
source_sha=b751226742033ad88fa900980af079ae99e01eb1c37cbbf6a6c3c91af7655deb
if [ -n "${HAMCLOCK_SOURCE_ARCHIVE:-}" ]; then
    cp "$HAMCLOCK_SOURCE_ARCHIVE" "$build/source.zip"
else
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
        --connect-timeout 20 --max-time 300 https://hamclock.com/ham/HamClock/ESPHamClock.zip -o "$build/source.zip"
fi
printf '%s  %s\n' "$source_sha" "$build/source.zip" | sha256sum --check --status
cp "$build/source.zip" "$output/hamclock-source-4.27.zip"
cp "$0" "$output/build-hamclock.sh"
unzip -q "$build/source.zip" -d "$build"
python3 - "$build/ESPHamClock/ArduinoLib/Arduino.cpp" <<'MONOTONIC'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
start = source.index('uint32_t millis(void)\n{')
end = source.index('\n}', start) + 2
old = source[start:end]
if 'gettimeofday' not in old:
    raise SystemExit('Unexpected HamClock millis implementation; refusing to patch')
new = """uint32_t millis(void)
{
    static const struct timespec origin = [] {
        struct timespec initial;
        if (clock_gettime(CLOCK_MONOTONIC, &initial) != 0)
            abort();
        return initial;
    }();
    struct timespec current;
    if (clock_gettime(CLOCK_MONOTONIC, &current) != 0)
        abort();
    int64_t ns = (int64_t)(current.tv_sec - origin.tv_sec)*1000000000LL
                 + current.tv_nsec - origin.tv_nsec;
    return (uint32_t)(ns/1000000);
}"""
path.write_text(source[:start] + new + source[end:])
MONOTONIC
make -C "$build/ESPHamClock" -j2 hamclock-800x480 \
    LDXXFLAGS='-LArduinoLib -LwsServer -Lzlib-hc -static -pthread' \
    LIBS="-larduino -lzlib-hc -lws $(pkg-config --static --libs x11) -ldl -lm"
package="$build/package"
mkdir -p "$package"
install -m 755 "$build/ESPHamClock/hamclock-800x480" "$package/hamclock-800x480"
strip "$package/hamclock-800x480"
if readelf -l "$package/hamclock-800x480" | grep -q INTERP || \
   readelf -d "$package/hamclock-800x480" | grep -q NEEDED; then
    echo 'Expected a fully static executable' >&2; exit 1
fi
"$package/hamclock-800x480" -v
install -m 644 "$build/ESPHamClock/LICENSE" "$package/LICENSE"
install -m 644 "$build/ESPHamClock/hamclock.1" "$package/hamclock.1"
{
    printf 'HamClock 4.27 Debian 13 amd64 X11 800x480\n'
    printf 'Source SHA256: %s\nPatch: monotonic-v1\nLinkage: static\n' "$source_sha"
    dpkg-query -W g++ libc6-dev libx11-dev libxcb1-dev
} > "$package/BUILD-INFO.txt"
archive=hamclock-4.27-debian13-amd64-static.tar.gz
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -C "$package" -czf "$output/$archive" hamclock-800x480 LICENSE hamclock.1 BUILD-INFO.txt
(cd "$output" && sha256sum "$archive" hamclock-source-4.27.zip build-hamclock.sh > SHA256SUMS)
cat "$output/SHA256SUMS"
