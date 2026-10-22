#!/bin/sh
# Run as root inside the installed Debian target, after configure-target.sh.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
source_url=https://hamclock.com/ham/HamClock/ESPHamClock.zip
source_sha=b751226742033ad88fa900980af079ae99e01eb1c37cbbf6a6c3c91af7655deb
build_id=4.27-x11-800x480-monotonic-v1
state=/var/lib/hamclock-installer
mkdir -p "$state" /usr/local/lib/hamclock /usr/local/share/doc/hamclock /usr/local/share/man/man1
exec 9>"$state/hamclock-install.lock"
flock -n 9 || { echo "Another HamClock installation is running" >&2; exit 1; }
# Also supports upgrading an already installed base system.
set -- build-essential libx11-dev curl ca-certificates unzip python3 x11-xserver-utils
missing=false
for package do
    [ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" = 'install ok installed' ] || missing=true
done
if [ "$missing" = true ]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
fi
# Reuse only the exact binary previously built from this pinned source.
if [ ! -x /usr/local/lib/hamclock/hamclock-800x480 ] ||
   [ "$(cat "$state/hamclock-source.sha256" 2>/dev/null || true)" != "$source_sha" ] ||
   [ "$(cat "$state/hamclock-build-id" 2>/dev/null || true)" != "$build_id" ]; then
    build=$(mktemp -d /var/tmp/hamclock-build.XXXXXX)
    trap 'rm -rf "$build"' EXIT HUP INT TERM
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
        --connect-timeout 20 --max-time 300 "$source_url" -o "$build/source.zip"
    if ! printf '%s  %s\n' "$source_sha" "$build/source.zip" | sha256sum --check --status; then
        echo "HamClock source checksum mismatch; refusing to build changed source" >&2
        exit 1
    fi
    # Extract and compile as the unprivileged application user.
    chown hamclock:hamclock "$build" "$build/source.zip"
    runuser -u hamclock -- unzip -q "$build/source.zip" -d "$build"
    # Upstream millis() uses wall time: NTP steps can turn wdDelay() negative.
    # Use a monotonic elapsed-time clock, preserving the uint32_t wrap contract.
    runuser -u hamclock -- python3 - "$build/ESPHamClock/ArduinoLib/Arduino.cpp" <<'MONOTONIC'
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
    runuser -u hamclock -- make -C "$build/ESPHamClock" -j2 hamclock-800x480
    install -m 0755 "$build/ESPHamClock/hamclock-800x480" /usr/local/lib/hamclock/.hamclock-new
    mv -f /usr/local/lib/hamclock/.hamclock-new /usr/local/lib/hamclock/hamclock-800x480
    install -m 0644 "$build/ESPHamClock/LICENSE" /usr/local/share/doc/hamclock/LICENSE
    install -m 0644 "$build/ESPHamClock/hamclock.1" /usr/local/share/man/man1/hamclock.1
    printf '%s\n' "$source_sha" > "$state/hamclock-source.sha256"
    printf '%s\n' "$build_id" > "$state/hamclock-build-id"
fi
cat > /usr/local/bin/hamclock <<'LAUNCH'
#!/bin/sh
exec /usr/local/lib/hamclock/hamclock-800x480 "$@"
LAUNCH
cat > /usr/local/bin/hamclock-session <<'SESSION'
#!/bin/sh
set -eu
# Import the actual XFCE session's X credentials; do not hard-code display :0.
systemctl --user import-environment DISPLAY XAUTHORITY
systemctl --user daemon-reload
if systemctl --user is-failed --quiet hamclock.service; then
    systemctl --user reset-failed hamclock.service
fi
exec systemctl --user start hamclock.service
SESSION
cat > /usr/local/bin/hamclock-kiosk <<'KIOSK'
#!/bin/sh
set -eu
# Settings are passed as separate, fixed arguments, never evaluated as shell code.
xset s off || true
xset -dpms || true
exec /usr/local/bin/hamclock -b hamclock.com:80 -f on -d "$HOME/.hamclock"
KIOSK
chmod 0755 /usr/local/bin/hamclock /usr/local/bin/hamclock-session /usr/local/bin/hamclock-kiosk
mkdir -p /etc/systemd/user
cat > /etc/systemd/user/hamclock.service <<'UNIT'
[Unit]
Description=HamClock graphical kiosk
StartLimitIntervalSec=120
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/hamclock-kiosk
Restart=on-failure
RestartSec=10
# HamClock keeps its rotating diagnostics in ~/.hamclock by default.
UNIT
install -d -o hamclock -g hamclock /home/hamclock/.config/autostart /home/hamclock/.hamclock
cat > /home/hamclock/.config/autostart/hamclock.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=HamClock
Comment=Start the HamClock kiosk in this graphical session
Exec=/usr/local/bin/hamclock-session
Terminal=false
OnlyShowIn=XFCE;
DESKTOP
chown hamclock:hamclock /home/hamclock/.config/autostart/hamclock.desktop
printf 'hamclock-4.27-x11-800x480-monotonic-v1\n' > "$state/hamclock-profile"
# A running user's service manager reloads automatically on the next login.
# For an upgrade in an active desktop, restart through hamclock-session as that user.
echo 'HamClock installed; it will start at the next XFCE login.'
