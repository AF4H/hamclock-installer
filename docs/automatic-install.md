# Direct boot and automatic installation

The USB image boots directly into Debian Installer in BIOS and UEFI mode. There
is no USB installation menu. Wi-Fi is preconfigured for SSID `AF4H`, WPA password
`h@mradio`; a linked wired connection can be selected by Debian's automatic
interface detection instead. DHCP remains enabled. These credentials are present
in the image, preseed and boot parameters. The boot priority is `critical` and
`netcfg/wireless_show_essids=manual` selects the supplied ESSID without the
otherwise unconditional high-priority scan-selection prompt. Both manual ESSID
questions are seeded for scan-success and scan-failure paths. Disk consent remains
a critical-priority question and still requires an explicit Yes.

After networking and hardware detection, the installer shows one erase consent
screen with the target disk path, model and capacity. **Yes authorizes erasing all
partitions, operating systems and files on that disk.** No is the default and
shuts down without authorizing partitioning. After Yes, guided whole-disk
partitioning, package installation and setup proceed automatically.

The small-appliance recipe uses a 256 MB EFI partition (or a BIOS boot partition),
256 MB swap and the remaining space for ext4 root. The desktop is XFCE with Xorg
and the appliance services, without Debian's broad desktop task/recommended office
and multimedia package bundle. Disk eligibility is a 4 GB minimum, not a claim
that every future package version or update will fit on that minimum.

The target must be the only writable, non-removable, non-USB physical disk of at
least 4 GB (4,000,000,000 bytes). Installer-media disks are excluded even when a USB device reports
itself as non-removable. Zero or multiple candidates stop automatic installation;
disconnect extra internal disks before retrying. Indirect loop/device-mapper
installation media is rejected. This is not a general-purpose multi-disk selector.
Disk consent is kept only in this boot's installer RAM and tied to the selected
path, model, size, serial and sysfs device path. GRUB is directed to the same disk.
Existing LVM/RAID configurations remain outside the tested acceptance matrix.

Use the firmware's one-time USB boot option when available, and remove the USB
media after installation. Leaving USB first in persistent firmware boot order may
return to the installer on reboot; a new explicit erase consent is required.

## SSH during installation

The installer loads Debian's `network-console` component from installation media,
starts SSH, and continues the local automatic installation without waiting for an
SSH connection. Connect to the address assigned by DHCP:

```sh
ssh installer@INSTALLER_IP
```

Password: `h@mradio`. Select **Start shell** for diagnostics. Avoid starting a
second installer menu while automatic installation is already running. The
installer's host name is `hamclock-install`; mDNS service discovery belongs to the
installed system, so use the DHCP IP during installation.

## SSH after installation

The installed account remains `hamclock`, password `h@mradio`, with password sudo.
OpenSSH is installed/enabled, password authentication is enabled and root SSH login
is disabled. The persistent random hostname is announced with Avahi:

```sh
ssh hamclock@hamclock-xxxxx.local
```

See [mDNS access](mdns.md) and [setup logs/recovery](binary-install.md).

## Installed-system boot

The installed GRUB menu is hidden with a zero-second normal timeout. `quiet splash`
and reduced console status output keep routine boot text out of view while
retaining journal diagnostics. Plymouth's graphical spinner is included in the
initramfs. Framebuffer/driver limitations can cause a fallback display; firmware
messages before GRUB remain under the machine firmware's control.

NetworkManager's wait-online unit is disabled so lack of an upstream network does
not delay the desktop. NetworkManager and Comitup still start normally and manage
connectivity. This is not a claim of a measured speed improvement on all hardware.
The failsafe-session issue and physical Wi-Fi verification remain separately
deferred; boot polish does not establish that those problems are resolved.

## Disposable VM validation (2026-10-22)

Image: `hamclock-debian13-amd64-automatic.iso`, SHA256
`3fb5fedfc1c57f1167431538eff3f1a9bfb7491c0d944a664e52b0371eecd658`.
Built from the verified Debian 13.7.0 amd64 netinst image; the extracted preseed
matched `scripts/build.py` output byte for byte. Sixteen local tests, preseed
syntax validation and ShellCheck passed.

Nested KVM tests used disposable disks only:

- BIOS and UEFI booted USB media directly, without an installation menu.
- Two eligible internal disks stopped automatic selection. Installer SSH login
  as `installer` with the supplied default password opened a root diagnostic shell.
  Both 24 GiB disks compared byte-for-byte equal to the blank reference after
  shutdown. This initial test preceded the additional fail-closed shutdown wrapper.
- On the final image, declining the default-No erase consent powered off the UEFI
  VM. Its target disk again compared equal to the blank reference.
- A writable 32 GiB USB installer configured to report itself as non-removable
  was excluded. The consent screen offered only the 24 GiB internal virtio disk.
  Approval completed partitioning, package installation and all six late setup
  stages without further input. The installer rebooted automatically. Installer
  SSH remained usable during installation.
- Installed SSH password login as `hamclock` and password sudo passed. SSH,
  LightDM, NetworkManager and Avahi were active; the SSH daemon reported
  `PermitRootLogin no` and `PasswordAuthentication yes`. Comitup was skipped
  because this guest had no wireless adapter.
- First installed UEFI boot displayed the graphical Debian 13 spinner. The
  selected theme and initramfs contents confirmed `spinner`; generated GRUB
  configuration used zero-second timeouts and the quiet/splash kernel options.
  NetworkManager wait-online was disabled. No comparative speed measurement
  is claimed.
- LightDM attempted autologin, but the reported **Unable to load a failsafe
  session** error reproduced. That separate issue remains unresolved; this is
  an installation/SSH/boot-configuration pass, not a working desktop or HamClock
  first-launch pass. The installed hostname was `hamclock-2ec7e`.

These tests do not cover Secure Boot, physical firmware/radios, existing
LVM/RAID layouts, or an iPXE installation.

## Small-disk and Wi-Fi selection correction

Debian 13's netcfg 1.197 resets the scan-selection question to unseen even when
`wireless_essid` is seeded. The new boot settings skip that high-priority question
and use the manual ESSID path; failed association/authentication still follows
Debian's error handling. Automatic interface detection still prefers a connected
wired interface. This fixes an observed selection prompt, not missing adapter
firmware or a radio authentication problem.

The former 16 GiB cutoff excluded marketed 8 GB and even some 16 GB disks. The new
cutoff is decimal 4 GB. Regression coverage checks the exact lower boundary, an
8 GB disk, firmware-specific recipes and USB exclusion. Eighteen local tests pass.

Source inspected: [Debian netcfg 1.197 source archive](https://deb.debian.org/debian/pool/main/n/netcfg/netcfg_1.197.tar.xz),
`wireless.c`, `netcfg_wireless_show_essids` and `netcfg_wireless_set_essid`.

The rebuilt `hamclock-debian13-amd64-small-disk.iso` has SHA256
`523b7a0e826427ac6c48e71b8a549af0d4832fd3f07a81f0e1ad612bdbf1fe90`.
Its extracted preseed matched the current generator output. A fresh disposable
UEFI guest with exactly 4,000,000,000 bytes of target storage completed partitioning,
all six setup stages and automatic reboot. SSH password login and sudo passed;
SSH, LightDM, NetworkManager and Avahi were active. The final layout was:

- EFI: 254,803,968 bytes.
- Root partition: 3,486,515,200 bytes. The mounted ext4 filesystem reported
  1,907,449,856 bytes used and 1,254,158,336 bytes available.
- Swap: 256,901,120 bytes.

XFCE, Xorg, D-Bus and Comitup were installed; the office suite was absent. The
failsafe-session error still reproduced, so this does not establish successful
HamClock graphical startup. BIOS recipe selection was fixture-tested; this new
small-disk recipe's full installation test was UEFI only.

Inside the actual Debian Installer, resetting the Wi-Fi scan question to unseen
and issuing `INPUT high netcfg/wireless_show_essids` returned skipped at critical
priority. The selected answer was `manual`; both ESSID answers were `AF4H`. The
critical erase confirmation remained visible with No selected before explicit
approval. This checks the real frontend behavior behind the selection fix; no
physical radio authentication or firmware compatibility is claimed.
