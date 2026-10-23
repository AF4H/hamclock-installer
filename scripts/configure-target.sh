#!/bin/sh
# Runs INSIDE the installed target via in-target, before its first boot.
set -eu
# Optional prefix is for filesystem-only fixture tests; command calls are mocked.
root=${HAMCLOCK_TEST_ROOT:-}
state="$root/var/lib/hamclock-installer"
mkdir -p "$state" "$root/etc/lightdm/lightdm.conf.d" "$root/etc/ssh/sshd_config.d"
if [ -f "$state/hostname" ]; then
    hostname=$(cat "$state/hostname")
else
    suffix=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-5)
    hostname="hamclock-$suffix"
fi
# Reject corrupt state rather than writing an invalid host identity.
printf '%s\n' "$hostname" | grep -Eq '^hamclock-[0-9a-f]{5}$'
printf '%s\n' "$hostname" > "$state/hostname"
printf '%s\n' "$hostname" > "$root/etc/hostname"
# Preserve IPv6 and other existing entries; replace Debian's local identity row.
sed '/^127\.0\.1\.1[[:space:]]/d' "$root/etc/hosts" > "$state/hosts.tmp"
printf '127.0.1.1\t%s\n' "$hostname" >> "$state/hosts.tmp"
cat "$state/hosts.tmp" > "$root/etc/hosts"
rm "$state/hosts.tmp"
usermod -aG sudo hamclock
cat > "$root/etc/lightdm/lightdm.conf.d/50-hamclock.conf" <<'CONF'
[Seat:*]
autologin-user=hamclock
autologin-user-timeout=0
user-session=xfce
autologin-session=xfce
CONF
cat > "$root/etc/ssh/sshd_config.d/00-hamclock.conf" <<'CONF'
PasswordAuthentication yes
PermitRootLogin no
CONF
# Validate installed services/configuration before allowing late_command success.
test -f "$root/usr/share/xsessions/xfce.desktop"
visudo -c
ssh-keygen -A
mkdir -p "$root/run/sshd"
sshd -t
systemctl enable ssh.service lightdm.service
systemctl set-default graphical.target
printf 'debian13-amd64-base-v1\n' > "$state/profile"
