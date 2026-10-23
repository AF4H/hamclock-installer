#!/bin/sh
# Run as root in the Debian target, after persistent hostname configuration.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
set -- avahi-daemon avahi-utils libnss-mdns
missing=false
for package do
    [ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" = 'install ok installed' ] || missing=true
done
if [ "$missing" = true ]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
fi
# Avahi's default host/address publication follows the persistent system hostname
# and discovers interfaces dynamically, including Wi-Fi connections added later.
# Leave its main configuration intact; no fixed interface or shared alias.
mkdir -p /etc/avahi/services
staging=$(mktemp -d /etc/avahi/services/.hamclock-mdns.XXXXXX)
trap 'rm -rf "$staging"' EXIT HUP INT TERM
# Publish complete XML files atomically; Avahi watches this directory live.
cat > "$staging/ssh.service" <<'SERVICE'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">HamClock %h SSH</name>
  <service>
    <type>_ssh._tcp</type>
    <port>22</port>
  </service>
</service-group>
SERVICE
cat > "$staging/web.service" <<'SERVICE'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">HamClock %h</name>
  <service>
    <type>_http._tcp</type>
    <port>8081</port>
    <txt-record>path=/live.html</txt-record>
  </service>
</service-group>
SERVICE
chmod 644 "$staging/ssh.service" "$staging/web.service"
mv -f "$staging/ssh.service" /etc/avahi/services/hamclock-ssh.service
mv -f "$staging/web.service" /etc/avahi/services/hamclock-web.service
systemctl enable avahi-daemon.service
# A fresh in-target install has no running daemon. A live upgrade should become
# discoverable immediately; Avahi reloads service files without losing clients.
if systemctl is-active --quiet avahi-daemon.service; then
    systemctl reload avahi-daemon.service
elif [ -d /run/systemd/system ]; then
    systemctl start avahi-daemon.service
fi
echo 'mDNS enabled: use <hostname>.local for SSH and port 8081/live.html for HamClock.'
