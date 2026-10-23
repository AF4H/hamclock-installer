#!/bin/sh
# Permit the appliance user's native HamClock power-off request, including SSH presence.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
if [ "$(dpkg-query -W -f='${Status}' polkitd 2>/dev/null || true)" != 'install ok installed' ]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends polkitd
fi
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/49-hamclock-power.rules <<'RULE'
// HamClock runs as a systemd user service, outside the graphical session scope.
// Allow only power-off for this appliance user, including another login such as SSH.
polkit.addRule(function(action, subject) {
    if (subject.user === "hamclock" &&
        (action.id === "org.freedesktop.login1.power-off" ||
         action.id === "org.freedesktop.login1.power-off-multiple-sessions")) {
        return polkit.Result.YES;
    }
});
RULE
chmod 644 /etc/polkit-1/rules.d/49-hamclock-power.rules
echo 'HamClock power-off authorization installed; no shutdown was requested.'
