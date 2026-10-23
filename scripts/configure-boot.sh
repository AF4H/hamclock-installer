#!/bin/sh
# Installed target only. Keep boot diagnostics in the journal, hide routine text.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as root' >&2; exit 1; }
set -- plymouth plymouth-themes
missing=false
for package do
    [ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" = 'install ok installed' ] || missing=true
done
if [ "$missing" = true ]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
fi
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-hamclock.cfg <<'CONF'
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_RECORDFAIL_TIMEOUT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=false rd.systemd.show_status=false"
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_DISABLE_OS_PROBER=true
CONF
# HamClock and Comitup handle network availability; no need to block the desktop.
systemctl disable NetworkManager-wait-online.service
if [ "$(plymouth-set-default-theme)" != spinner ]; then
    plymouth-set-default-theme -R spinner
fi
update-grub
echo 'Graphical boot splash and zero-second GRUB timeout configured.'
