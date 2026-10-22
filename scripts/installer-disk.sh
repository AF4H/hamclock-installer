#!/bin/sh
# Debian Installer only. Select one fixed disk, then require explicit erase consent.
set -eu
root=${HAMCLOCK_TEST_ROOT:-}
# shellcheck disable=SC1090
. "${HAMCLOCK_DEBCONF:-/usr/share/debconf/confmodule}"
stop() {
    db_subst hamclock/disk-error REASON "$1"
    db_fset hamclock/disk-error seen false
    db_input critical hamclock/disk-error || true
    db_go || true
    exit 1
}
mkdir -p "$root/tmp"
cat > "$root/tmp/hamclock-disk.templates" <<'TEMPLATES'
Template: hamclock/erase-disk
Type: boolean
Default: false
Description: Install HamClock and erase ${DISK}?
 Target: ${MODEL} (${SIZE} GB), ${DISK}.
 .
 ALL partitions, operating systems, and files on this disk will be erased.
 After choosing Yes, installation is automatic. Choose No to shut down.

Template: hamclock/disk-error
Type: error
Description: Automatic installation stopped
 ${REASON}
 .
 No disk has been authorized for erasing. Disconnect extra internal disks or
 provide a suitable internal disk, then restart the installer.
TEMPLATES
debconf-loadtemplate hamclock "$root/tmp/hamclock-disk.templates"
count=0
disk=
for block in "$root"/sys/block/*; do
    [ -d "$block" ] || continue
    name=${block##*/}
    case "$name" in sd*|vd*|xvd*|nvme*n*|mmcblk*) ;; *) continue ;; esac
    [ "$(cat "$block/removable")" = 0 ] || continue
    [ "$(cat "$block/ro")" = 0 ] || continue
    sectors=$(cat "$block/size")
    [ "$sectors" -ge 7812500 ] || continue
    case "$(readlink -f "$block/device")" in */usb*|*/USB*) continue ;; esac
    # Exclude any physical disk backing directly mounted installer media.
    media=false
    while read -r source mountpoint rest; do
        case "$mountpoint" in /cdrom|/hd-media|/isodevice|/run/live/medium)
            case "$source" in
                /dev/"$name"|/dev/"$name"[0-9]*|/dev/"$name"p[0-9]*) media=true ;;
                /dev/loop*|/dev/mapper/*) stop 'Installer media uses an indirect device; automatic disk selection is unsafe.' ;;
            esac ;;
        esac
    done < "$root/proc/mounts"
    [ "$media" = false ] || continue
    count=$((count + 1))
    disk=/dev/$name
    selected=$block
    selected_sectors=$sectors
done
[ "$count" -eq 1 ] || stop "Expected exactly one writable, non-USB internal disk of at least 4 GB; found $count."
model=$(cat "$selected/device/model" 2>/dev/null || printf '%s' "${disk##*/}")
size=$((selected_sectors * 512 / 1000000000))
fingerprint_selected() {
    current_sectors=$(cat "$selected/size") || return 1
    current_model=$(cat "$selected/device/model" 2>/dev/null || printf '%s' "${disk##*/}")
    current_serial=$(cat "$selected/device/serial" 2>/dev/null || cat "$selected/device/cid" 2>/dev/null || true)
    printf '%s\n' "$disk" "$current_sectors" "$current_model" "$current_serial" "$(readlink -f "$selected/device")" | sha256sum | cut -d' ' -f1
}
fingerprint=$(fingerprint_selected)
marker="$root/tmp/hamclock-disk-consent"
if [ "$(cat "$marker" 2>/dev/null || true)" != "$fingerprint" ]; then
    db_subst hamclock/erase-disk DISK "$disk"
    db_subst hamclock/erase-disk MODEL "$model"
    db_subst hamclock/erase-disk SIZE "$size"
    db_set hamclock/erase-disk false
    db_fset hamclock/erase-disk seen false
    db_input critical hamclock/erase-disk || true
    db_go || exit 1
    db_get hamclock/erase-disk
    if [ "$RET" != true ]; then
        poweroff
        exit 1
    fi
    printf '%s\n' "$fingerprint" > "$marker"
fi
[ "$(fingerprint_selected)" = "$fingerprint" ] || stop 'The selected disk changed while awaiting confirmation.'
# Small-appliance layout: bounded swap, remaining space for root; no 8 GB root
# minimum from Debian's desktop atomic recipe. Firmware determines boot partition.
if [ -d "$root/sys/firmware/efi" ]; then
    # Literal partman recipe variables.
    # shellcheck disable=SC2016
    boot='256 256 256 free $primary{ } method{ efi } format{ } .'
else
    # Literal partman recipe variables.
    # shellcheck disable=SC2016
    boot='1 1 1 free $bios_boot{ } method{ biosgrub } .'
fi
db_set partman-auto/expert_recipe "hamclock :: $boot 2500 10000 -1 ext4 method{ format } format{ } use_filesystem{ } filesystem{ ext4 } mountpoint{ / } . 256 256 256 linux-swap method{ swap } format{ } ."
# Set both destinations from the authorized disk; never rely on first-disk ordering.
db_set partman-auto/disk "$disk"
db_set grub-installer/bootdev "$disk"
logger -t hamclock-installer "Erase authorized for $disk ($model, $size GB)"
