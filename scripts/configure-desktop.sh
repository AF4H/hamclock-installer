#!/bin/sh
# Run as root in the target; also upgrades an existing HamClock installation.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
mkdir -p /etc/systemd/logind.conf.d /usr/local/bin
cat > /etc/systemd/logind.conf.d/50-hamclock.conf <<'CONF'
[Login]
IdleAction=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
CONF
# Enforce the appliance policy even if a desktop component requests sleep.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
cat > /usr/local/bin/hamclock-desktop-settings <<'SESSION'
#!/bin/sh
set -eu
# Update through the running settings daemon, never overwrite its live XML files.
set_property() {
    xfconf-query --channel "$1" --property "$2" --create --type "$3" --set "$4"
}
channel=xfce4-power-manager
prefix=/xfce4-power-manager
set_property "$channel" "$prefix/inactivity-on-ac" uint 0
set_property "$channel" "$prefix/inactivity-on-battery" uint 0
set_property "$channel" "$prefix/dpms-enabled" bool false
set_property "$channel" "$prefix/presentation-mode" bool true
set_property "$channel" "$prefix/lock-screen-suspend-hibernate" bool false
set_property "$channel" "$prefix/lid-action-on-ac" uint 0
set_property "$channel" "$prefix/lid-action-on-battery" uint 0
set_property xfce4-session /shutdown/LockScreen bool false
set_property xfce4-screensaver /saver/enabled bool false
set_property xfce4-screensaver /saver/idle-activation/enabled bool false
set_property xfce4-screensaver /lock/enabled bool false
set_property xfce4-screensaver /lock/sleep-activation bool false
xset s off
xset s noblank
# Some virtual displays have no DPMS extension.
xset -dpms || true
SESSION
chmod 755 /usr/local/bin/hamclock-desktop-settings
# Name the parent explicitly: install -d otherwise creates it owned by root.
install -d -o hamclock -g hamclock /home/hamclock/.config /home/hamclock/.config/autostart
cat > /home/hamclock/.config/autostart/hamclock-desktop-settings.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=HamClock always-on desktop
Exec=/usr/local/bin/hamclock-desktop-settings
OnlyShowIn=XFCE;
Terminal=false
DESKTOP
# Prevent a legacy locker, if present, from adding a second password prompt.
for locker in light-locker xscreensaver; do
    cat > "/home/hamclock/.config/autostart/$locker.desktop" <<EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=$locker
Hidden=true
EOF_DESKTOP
done
chown hamclock:hamclock /home/hamclock/.config/autostart/hamclock-desktop-settings.desktop \
    /home/hamclock/.config/autostart/light-locker.desktop /home/hamclock/.config/autostart/xscreensaver.desktop
# Apply to a running desktop when upgrading, using its existing user bus.
# Stop already-running legacy lockers in an existing installation.
for locker in light-locker xscreensaver; do
    pkill -u hamclock -x "$locker" || true
done
uid=$(id -u hamclock)
if [ -S "/run/user/$uid/bus" ]; then
    # The graphical service manager already has DISPLAY/XAUTHORITY from login.
    runuser -u hamclock -- env XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        systemd-run --user --wait --collect /usr/local/bin/hamclock-desktop-settings
fi
echo 'Automatic sleep and locking disabled. Reboot once to apply all login/lid settings.'
