#!/bin/sh
# Run as root inside the installed Debian 13 amd64 target.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
if [ "$ID" != debian ] || [ "$VERSION_ID" != 13 ]; then
    echo 'Debian 13 required' >&2; exit 1;
fi
[ "$(dpkg --print-architecture)" = amd64 ] || { echo 'Debian amd64 required' >&2; exit 1; }
# Fixed release and checksum: never download a mutable "latest" binary.
binary_url=https://github.com/AF4H/hamclock-installer/releases/download/hamclock-bin-1525bad751d441ba9b1ff252946351e2fc797759/hamclock-4.27-debian13-amd64-static.tar.gz
binary_sha=149c5cab1c4620afda7e3ad2e7e94a8d656b97bc613c96f01450e6f9f316bc06
state=/var/lib/hamclock-installer
mkdir -p "$state" /usr/local/lib/hamclock /usr/local/share/doc/hamclock /usr/local/share/man/man1
exec 9>"$state/hamclock-install.lock"
flock -n 9 || { echo 'Another HamClock installation is running' >&2; exit 1; }
# No compiler, headers, source archive or Python needed for binary installation.
set -- curl ca-certificates x11-xserver-utils libglib2.0-bin
missing=false
for package do
    [ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" = 'install ok installed' ] || missing=true
done
if [ "$missing" = true ]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
fi
if [ "$(cat "$state/hamclock-archive.sha256" 2>/dev/null || true)" != "$binary_sha" ] ||
   ! sha256sum --check --status "$state/hamclock-binary.sha256" 2>/dev/null; then
    download=$(mktemp -d /var/tmp/hamclock-download.XXXXXX)
    trap 'rm -rf "$download"' EXIT HUP INT TERM
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
        --connect-timeout 20 --max-time 300 "$binary_url" -o "$download/binary.tar.gz"
    if ! printf '%s  %s\n' "$binary_sha" "$download/binary.tar.gz" | sha256sum --check --status; then
        echo 'HamClock binary checksum mismatch; existing executable was preserved' >&2; exit 1
    fi
    # Reject unexpected paths before extraction, even for a pinned archive.
    expected=$(printf '%s\n' BUILD-INFO.txt LICENSE hamclock-800x480 hamclock.1)
    [ "$(tar -tzf "$download/binary.tar.gz" | LC_ALL=C sort)" = "$expected" ] || {
        echo 'Unexpected binary archive contents' >&2; exit 1;
    }
    tar --no-same-owner --no-same-permissions -xzf "$download/binary.tar.gz" -C "$download"
    for file in hamclock-800x480 LICENSE hamclock.1 BUILD-INFO.txt; do
        [ -f "$download/$file" ] && [ ! -L "$download/$file" ] || exit 1
    done
    install -m 755 "$download/hamclock-800x480" /usr/local/lib/hamclock/.hamclock-new
    mv -f /usr/local/lib/hamclock/.hamclock-new /usr/local/lib/hamclock/hamclock-800x480
    install -m 644 "$download/LICENSE" /usr/local/share/doc/hamclock/LICENSE
    install -m 644 "$download/BUILD-INFO.txt" /usr/local/share/doc/hamclock/BUILD-INFO.txt
    install -m 644 "$download/hamclock.1" /usr/local/share/man/man1/hamclock.1
    sha256sum /usr/local/lib/hamclock/hamclock-800x480 > "$state/hamclock-binary.sha256"
    printf '%s\n' "$binary_sha" > "$state/hamclock-archive.sha256"
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
[ ! -x /usr/local/bin/hamclock-defaults ] || /usr/local/bin/hamclock-defaults
[ ! -x /usr/local/bin/hamclock-display ] || /usr/local/bin/hamclock-display || true
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
# Name the parent explicitly: install -d otherwise creates it owned by root.
install -d -o hamclock -g hamclock /home/hamclock/.config /home/hamclock/.config/autostart /home/hamclock/.hamclock
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
# Provide an application-menu entry and an executable desktop launcher.
mkdir -p /usr/local/share/applications
cat > /usr/local/share/applications/hamclock.desktop <<'SHORTCUT'
[Desktop Entry]
Type=Application
Name=HamClock
Comment=Open the HamClock station
Exec=/usr/local/bin/hamclock-session
Icon=preferences-system-time
Terminal=false
Categories=Utility;
StartupNotify=false
SHORTCUT
install -d -o hamclock -g hamclock /home/hamclock/Desktop
install -m 755 -o hamclock -g hamclock /usr/local/share/applications/hamclock.desktop /home/hamclock/Desktop/HamClock.desktop
printf 'hamclock-4.27-static-amd64-monotonic-v1\n' > "$state/hamclock-profile"
# A running user's service manager reloads automatically on the next login.
# For an upgrade in an active desktop, restart through hamclock-session as that user.
echo 'HamClock installed; it will start at the next XFCE login.'
