# Direct boot and automatic installation

The USB image boots directly into Debian Installer in BIOS and UEFI mode. There
is no USB installation menu. Wi-Fi is preconfigured for SSID `AF4H`, WPA password
`h@mradio`; a linked wired connection can be selected by Debian's automatic
interface detection instead. DHCP remains enabled. These credentials are present
in the image, preseed and boot parameters.

After networking and hardware detection, the installer shows one erase consent
screen with the target disk path, model and capacity. **Yes authorizes erasing all
partitions, operating systems and files on that disk.** No is the default and
shuts down without authorizing partitioning. After Yes, guided whole-disk
partitioning, package installation and setup proceed automatically.

The target must be the only writable, non-removable, non-USB physical disk of at
least 16 GiB. Installer-media disks are excluded even when a USB device reports
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
