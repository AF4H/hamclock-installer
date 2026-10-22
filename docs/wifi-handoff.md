# Debian Installer Wi-Fi handoff

The second bare-metal syslog got past APT and package installation, then stopped
with `Move Wi-Fi configuration from /etc/network/interfaces to NetworkManager
before retrying`. This was the installer's own guard: Debian Installer had left
its working Wi-Fi connection in ifupdown format. That normal configuration should
be migrated automatically rather than treated as an error.

The Wi-Fi stage now recognizes DHCP IPv4 Wi-Fi stanzas in `/etc/network/interfaces`
and `interfaces.d`. It preserves the selected SSID and WPA-PSK passphrase or
64-digit hashed PSK, and also supports open networks and an accompanying IPv6 auto
stanza. `nmcli --offline` validates and serializes a native NetworkManager profile
without requiring a running daemon in the installer chroot. Values are passed as
separate arguments, with no shell interpretation or credential logging.

All profiles are generated before any legacy network entry is removed. Files have
root-only mode 0600 and a deterministic UUID/path for safe retries. The profile is
not bound to a hardware interface name. Its autoconnect priority is lower than
existing default-priority profiles, so an operator's saved connection remains
preferred. Existing unrelated profiles are retained; a customized file at the
migration's own destination is not overwritten.

Only migrated Wi-Fi stanzas and their `auto`/`allow-hotplug` interface names are
removed. Loopback, wired configuration, include directives and other interface
names are preserved. Originals are stored in
`/var/lib/hamclock-installer/network-backup/etc/network/`, inside a mode-0700
directory with mode-0600 files. The script does not restart networking, disconnect
an interface or activate a connection; reboot completes the handoff. On a live
system NetworkManager may notice changed configuration, so use a console when
repairing the active Wi-Fi connection.

Custom static addressing, enterprise authentication, external `wpa-conf` files,
and unsupported interface hooks/options still stop with the original network files
retained. They need deliberate manual migration. This change does not introduce a
preset SSID/password: it carries forward the network selected during installation.

## Recovery and new media

Use the rebuilt Wi-Fi-handoff ISO for another installation attempt, or run the
updated generated `repair-hamclock.sh` after finishing and booting the installed
Debian system, followed by a reboot. The repair script runs the same stages as the
ISO and does not repartition disks. See [binary installation/recovery](binary-install.md).

## Validation, 2026-10-22

Eleven local tests pass. The new migration tests cover credential characters,
mixed wired/Wi-Fi activation lists, wired static settings and repeated wired
hooks, IPv6 auto, restrictive profile/backup permissions, retries, preservation of
operator profiles, unsupported legacy configuration and NM rejection without
removing credentials. Unit tests isolate serialization; the actual NM offline
serializer is exercised in the VM.

A disposable Debian 13 guest was given an installer-style `wlan0` DHCP stanza and
a WPA2 PSK stored as a 64-digit hash. Two `mac80211_hwsim` radios supplied a client
and an independent hostapd/DHCP access point in a separate namespace. The generated
full recovery script migrated the connection and reached `HamClock-stage=complete`.
After restarting NetworkManager in this test VM, it automatically used the migrated
profile, associated with the AP, obtained 192.0.2.144 via DHCP and pinged 192.0.2.1
with no packet loss. Ethernet remained connected. Comitup reached CONNECTED with
the migrated connection, while HamClock stayed active. The generated keyfile had
mode 0600 and the private backup retained the original legacy configuration. A repeat full recovery run preserved
the migrated profile checksum and left Wi-Fi and Ethernet connected. The real
offline serializer also passed with an unusable system-bus address, including an
SSID/password containing spaces and special characters.

This validates migration and actual profile use in a running guest, including a
NetworkManager restart. It does not establish a fresh full ISO installation,
physical adapter operation or a complete Wi-Fi boot/power-cycle test. Those remain
for the next bare-metal test. The subsequently authorized boot appearance, disk
automation, direct USB boot and preset Wi-Fi changes are described in
[automatic installation](automatic-install.md).

Reference: [NetworkManager keyfile format](https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html).
