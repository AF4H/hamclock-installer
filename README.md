# HamClock installer

Initial **Debian 13 (trixie), amd64** base installer. Implementation for review;
no VM or hardware installation has been completed yet. HamClock itself and
Comitup are intentionally deferred.

## Installed base

- DHCP on the interface selected by Debian Installer (wired networking recommended).
- `hamclock` user, initial password `h@mradio`, password-based sudo, locked root login.
- OpenSSH server with password authentication, root SSH login disabled.
- XFCE with LightDM graphical autologin as `hamclock`.
- Persistent `hamclock-xxxxx` hostname, five random hexadecimal characters generated
  during target configuration. It is saved under `/var/lib/hamclock-installer/hostname`
  and reused if configuration is retried. This is not a globally unique identifier;
  collisions are possible. The installer initially uses `hamclock-install`.
- US English keyboard/locale and UTC; these are editable profile defaults.

The shared password and automatic desktop login are intentional requested defaults.
Change the password with `passwd` after installation before exposing SSH to untrusted
networks. The preseed contains the initial password and must be treated accordingly.

## Build and validate

Requires Python 3.11+, POSIX shell and `debconf-set-selections` (Debian `debconf`).

```sh
python3 scripts/build.py
python3 -m unittest discover -s tests -v
sh -n scripts/configure-target.sh
```

`build/preseed.cfg` embeds the target script, avoiding a second late-install script
fetch. Both transports use exactly this profile. Do not edit the generated file.
CI also runs ShellCheck. Static checks do not establish installer runtime correctness.

## Disk safety and interaction

Boot with `auto=true priority=high`. No partition method, disk, recipe, bootloader
disk or destructive confirmation is preseeded. The operator must select a disk,
choose the partition layout, and approve Debian's write/erase confirmation screens.
Existing LVM/RAID may introduce additional confirmations. Review the device model,
size and partitions carefully, especially when a USB installer is attached.
Do not add `priority=critical`, `partman-auto/disk`, or automated confirmation answers.
This is a partially automated installer and needs a local console.

## iPXE

Build the preseed and serve it from a trusted deployment server. Edit `base` in
`boot/hamclock.ipxe`, then chain that script from an existing iPXE setup. The example
192.0.2.1 address is a documentation placeholder. The iPXE build needs HTTPS support
and a working trust configuration for the Debian kernel/initrd URLs. Use matched
kernel and initrd from the same Debian installer release; for repeatable deployment,
cache and verify a matched pair rather than relying on the moving `current` path.
The boot parameters configure DHCP before the network preseed can be fetched.
An iPXE key prompt precedes boot. BIOS/UEFI iPXE loading and DHCP infrastructure
are provided by the deployment environment, not by this repository.

## Bootable USB image

Install `xorriso` and obtain an official **Debian 13 amd64 netinst hybrid ISO**.
Independently verify Debian's signed SHA256SUMS using a trusted Debian signing key,
then supply the corresponding checksum:

```sh
python3 scripts/build-usb.py debian-13.x.x-amd64-netinst.iso EXPECTED_SHA256 hamclock-amd64.iso
```

The builder checks the input hash, embeds the shared preseed, appends a HamClock
menu entry to BIOS ISOLINUX and UEFI GRUB menus, and asks xorriso to replay the
original hybrid boot metadata. It keeps stock entries and never writes a physical
disk. Select **HamClock Debian 13 (interactive disks)** in the resulting boot menu.
Write the resulting ISO using a trusted image writer, verifying the USB device's
identity before erasing it. Remove installation media after installation.

This workflow is implemented but the remastered ISO has not been built or booted
in this environment. It requires the netinst menu/path layout expected by the
builder; extraction fails for unsupported layouts. Internet access remains necessary
for package installation; this is not an offline installer. Remastering does not
establish Secure Boot compatibility: test it explicitly, alongside legacy BIOS and
UEFI without Secure Boot.

## Validation status and acceptance plan

Validated locally: preseed parser (`debconf-set-selections --checkonly`), shell
syntax, embedded script equality, absence of partition/bootloader selections,
hostname generation/persistence/corrupt-state rejection, preserved hosts entries,
and target configuration using mocked system commands. Python sources compile.
ShellCheck is configured in CI but unavailable locally. Neither xorriso nor QEMU
is installed here. Service commands in fixture tests are mocks, not runtime tests.

Before recommending deployment, test **both transports** in disposable VMs first:

1. BIOS and UEFI boot, DHCP and preseed retrieval, package availability on trixie.
2. Two virtual disks: operator selects the intended disk, cancellation at final
   destructive confirmation leaves both unchanged, approval modifies only that disk.
   Repeat with existing partitions, LVM/RAID, and a USB installer attached.
3. Confirm install success and late-command errors are visible; check installer logs.
4. Reboot twice: hostname stays fixed, DHCP works, XFCE autologin appears.
5. Check `id hamclock`, `sudo -v`, SSH password login, rejected root SSH login,
   `systemctl status ssh lightdm`, `lightdm --show-config`, and `sshd -T`.
6. Test network/download failure, firmware requirements, and Secure Boot separately.
7. Repeat on actual amd64 hardware and record ISO version/checksums, firmware mode,
   transport and results before claiming end-to-end support.

## Next integrations

Keep base OS configuration shared across iPXE and USB. Add a versioned, idempotent
HamClock kiosk stage only after the base acceptance tests pass; decide executable,
display settings and recovery behavior then. Add Comitup in a separate stage with
explicit ownership of network interfaces (avoid competing DHCP/network managers),
Wi-Fi hardware/firmware tests and recovery-access tests. Neither integration should
bypass disk confirmations or regenerate the installed host identity.

## Reference assumptions

- [Debian trixie preseed reference](https://www.debian.org/releases/trixie/amd64/apbs04.en.html)
- [Preseed format and syntax validation](https://www.debian.org/releases/trixie/amd64/apbs03.en.html)
- [Debian amd64 installation guide](https://www.debian.org/releases/trixie/amd64/)

A preseed parser accepts syntax without proving that every template, package,
LightDM PAM configuration or boot-image assumption behaves as intended. The test
matrix above is the remaining evidence required for installation support.
