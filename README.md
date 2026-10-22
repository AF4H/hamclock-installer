# HamClock installer

**Debian 13 (trixie), amd64** HamClock installer. Implementation for review;
disposable nested-KVM tests cover the base profile and automatic installer.
See [the test report](docs/vm-test-2026-10-21.md) for exact coverage and remaining
tests. The user also reports a successful physical UEFI installation, including
autologin and networking. The installer now downloads and starts a prebuilt static HamClock binary; Comitup supplies a Wi-Fi setup hotspot when an AP-capable adapter is available.
See [HamClock installation and startup](docs/hamclock-integration.md) for scope and
validation of this new stage.

## Installed base

- DHCP on the interface selected by Debian Installer (wired networking recommended).
- `hamclock` user, initial password `h@mradio`, password-based sudo, locked root login.
- OpenSSH server with password authentication, root SSH login disabled.
- mDNS hostname and SSH/HamClock service discovery via Avahi; see
  [local-network access](docs/mdns.md).
- XFCE with LightDM graphical autologin as `hamclock`.
- Always-on desktop: automatic sleep, screen blanking and locking disabled on AC
  and battery; see [existing-install update and validation](docs/always-on.md).
- Checksum-pinned, prebuilt static HamClock 4.27 X11 binary (800×480), started fullscreen by a user
  service at XFCE login, with restart on failure. Callsign/location setup remains
  interactive on first launch.
- Comitup setup hotspot with common non-free Wi-Fi firmware installed; see
  [Wi-Fi setup and test coverage](docs/wifi.md).
- Persistent `hamclock-xxxxx` hostname, five random hexadecimal characters generated
  during target configuration. It is saved under `/var/lib/hamclock-installer/hostname`
  and reused if configuration is retried. This is not a globally unique identifier;
  collisions are possible. The installer initially uses `hamclock-install`.
- US English keyboard/locale and UTC; these are editable profile defaults.

The shared password and automatic desktop login are intentional requested defaults.
Change the password with `passwd` after installation before exposing SSH to untrusted
networks. The preseed contains the initial password and must be treated accordingly.

## Build and validate

Local validation requires Python 3.11+, `g++` with C++17 support, a POSIX shell
and `debconf-set-selections` (Debian `debconf`).

```sh
python3 scripts/build.py
python3 -m unittest discover -s tests -v
sh -n scripts/configure-target.sh
```

`build/preseed.cfg` embeds the setup scripts; `build/repair-hamclock.sh` runs the
same stages on an existing installation. HamClock is downloaded as a fixed,
checksum-verified binary release; the installation target does not compile it. Both transports use exactly this profile. Do not edit the generated file.
CI also runs ShellCheck. Static checks do not establish installer runtime correctness.

## Automatic installation and disk consent

The USB boots directly into the installer. Networking uses DHCP and the preset
Wi-Fi `AF4H` / `h@mradio` when selected by automatic interface detection. After
hardware/network setup, one explicit confirmation authorizes erasing the displayed
disk. **All existing data on that disk is erased.** No is the default and shuts down.
The disk must be the only eligible internal disk; USB/media devices are excluded
and ambiguous layouts stop. Partitioning and later setup are automatic after Yes.
See [automatic install, disk rules and SSH access](docs/automatic-install.md).

Installer SSH uses `installer` / `h@mradio`; installed SSH uses `hamclock` /
`h@mradio`. The installed GRUB timeout is zero with a graphical Plymouth splash.

## iPXE

Build the preseed and serve it from a trusted deployment server. Edit `base` in
`boot/hamclock.ipxe`, then chain that script from an existing iPXE setup. The example
192.0.2.1 address is a documentation placeholder. The iPXE build needs HTTPS support
and a working trust configuration for the Debian kernel/initrd URLs. Use matched
kernel and initrd from the same Debian installer release; for repeatable deployment,
cache and verify a matched pair rather than relying on the moving `current` path.
The boot parameters configure DHCP before the network preseed can be fetched.
The stock netboot initrd may lack non-free firmware: use wired networking with an
included driver, or supply Debian's matching firmware archive in your deployment
initrd. Enabling firmware in the preseed cannot fix networking before it is fetched.
The same disk consent screen precedes partitioning. BIOS/UEFI iPXE loading and DHCP infrastructure
are provided by the deployment environment, not by this repository.

## Bootable USB image

Install `xorriso` and obtain an official **Debian 13 amd64 netinst hybrid ISO**.
Independently verify Debian's signed SHA256SUMS using a trusted Debian signing key,
then supply the corresponding checksum:

```sh
python3 scripts/build-usb.py debian-13.x.x-amd64-netinst.iso EXPECTED_SHA256 hamclock-amd64.iso
```

The builder checks the input hash, embeds the shared preseed, replaces the BIOS ISOLINUX and UEFI GRUB menus with direct installer boot, and asks xorriso to replay the
original hybrid boot metadata. The builder never writes a physical disk. The resulting media boots straight
into the installer and then asks for explicit disk-erasing consent.
Write the resulting ISO using a trusted image writer, verifying the USB device's
identity before erasing it. Remove installation media after installation.

The remastered Debian 13.7.0 ISO was built successfully and installed in a BIOS
VM; a separate OVMF test reached its UEFI menu. It requires the netinst menu/path
layout expected by the builder; extraction fails for unsupported layouts. Internet access remains necessary
for package installation; this is not an offline installer. Remastering does not
establish Secure Boot compatibility: test it explicitly, alongside legacy BIOS and
UEFI without Secure Boot.

## Validation status and acceptance plan

Validated locally: preseed parser (`debconf-set-selections --checkonly`), shell
syntax, embedded script equality, disk consent and matching partition/bootloader destinations,
hostname generation/persistence/corrupt-state rejection, preserved hosts entries,
and target configuration using mocked system commands. Python sources compile.
The base profile passed GitHub CI. Sixteen local tests and ShellCheck cover the
extended profile, including first-session startup, compiled elapsed-clock behavior,
installer-media APT cleanup, Wi-Fi handoff/credential preservation and failing-stage status/logs. The USB builder regression
test covers read-only extracted menu files. A real BIOS VM installation also passed
DHCP, disk selection/erase cancellation, SSH password login, sudo, XFCE autologin,
and hostname persistence across reboot. The second virtual disk remained unchanged.
See [the test report](docs/vm-test-2026-10-21.md) for runtime evidence; fixture service
commands remain mocks. Those BIOS results describe the earlier manual-disk profile.
Current direct-boot, disk-consent, installer-SSH and UEFI automatic-install results
are recorded in [automatic installation](docs/automatic-install.md). The user
confirmed successful UEFI base installation, autologin and networking on physical
hardware. Hardware model and Secure Boot state were not supplied.

Before recommending deployment, complete the remaining acceptance matrix for
**both transports**; the initial BIOS ISO result covers only part of it:

1. BIOS and UEFI boot, DHCP and preseed retrieval, package availability on trixie.
2. Two virtual disks: automatic installation stops without selecting either disk.
   With one eligible disk, declining the initial erase consent leaves it unchanged.
   Repeat with existing partitions, LVM/RAID, and a USB installer attached.
3. Confirm install success and late-command errors are visible; check installer logs.
4. Reboot twice: hostname stays fixed, DHCP works, XFCE autologin appears.
5. Check `id hamclock`, `sudo -v`, SSH password login, rejected root SSH login,
   `systemctl status ssh lightdm`, `lightdm --show-config`, and `sshd -T`.
6. Test network/download failure, firmware requirements, and Secure Boot separately.
7. Repeat on actual amd64 hardware and record ISO version/checksums, firmware mode,
   transport and results before claiming end-to-end support.

## Application and Wi-Fi stages

Base OS, HamClock and Comitup configuration are shared across iPXE and USB.
If late setup fails, the complete stage log is `/var/log/hamclock-installer.log`
on the installed target (`/target/var/log/hamclock-installer.log` while still in
Debian Installer). See [failure recovery](docs/binary-install.md).
The stages also support upgrades of the previously installed base. See
[HamClock](docs/hamclock-integration.md) and [Wi-Fi](docs/wifi.md) for usage,
network ownership, firmware limitations and the distinction between VM upgrade
checks and fresh installer tests. The initial erase consent remains required;
installed identity persists across recovery runs.

## Reference assumptions

- [Debian trixie preseed reference](https://www.debian.org/releases/trixie/amd64/apbs04.en.html)
- [Preseed format and syntax validation](https://www.debian.org/releases/trixie/amd64/apbs03.en.html)
- [Debian amd64 installation guide](https://www.debian.org/releases/trixie/amd64/)

A preseed parser accepts syntax without proving that every template, package,
LightDM PAM configuration or boot-image assumption behaves as intended. The test
matrix above is the remaining evidence required for installation support.
