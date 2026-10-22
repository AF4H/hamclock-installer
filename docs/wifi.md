# Wi-Fi setup

The shared installer installs Debian's Comitup package and NetworkManager, plus
`firmware-iwlwifi`, `firmware-realtek`, `firmware-atheros`, `firmware-brcm80211`,
`firmware-mediatek`, `firmware-libertas` and `firmware-misc-nonfree` from trixie's
`non-free-firmware` component. This provides common firmware for changing hardware;
it does not supply every vendor driver or guarantee access-point support.

After installation, with a supported Wi-Fi adapter and no saved usable Wi-Fi
connection:

1. Connect a phone or laptop to the machine's `hamclock-xxxxx-setup` Wi-Fi network.
2. Enter the initial hotspot password `h@mradio`.
3. Open `http://10.41.0.1` if the captive setup page does not appear automatically.
4. Select your home network and enter its password. The hotspot closes while the
   machine connects. The saved connection is used after reboot. An unavailable
   saved network causes Comitup to offer setup again.

HamClock keeps running during setup. Its Internet features need working upstream
networking. Ethernet DHCP remains usable, including on machines without Wi-Fi.
The hotspot password is independent of the Linux account password: change it in
`/etc/comitup.conf` and reboot. Saved Wi-Fi credentials belong to NetworkManager;
rerunning the installer preserves them and subsequent changes to Comitup's config.

## Existing installations

Copy `scripts/install-wifi.sh` to the machine, run `sudo sh install-wifi.sh`, and
reboot. Internet access is required for package installation. This changes only
the target system, not the computer used to build its USB image. Existing wired
configuration is preserved. A conflicting legacy Wi-Fi configuration in
`/etc/network/interfaces` or `interfaces.d` is rejected; migrate that Wi-Fi
connection to NetworkManager before retrying. Custom interfaces sourced from other
locations need manual review. XFCE installations normally already use
NetworkManager and leave only loopback in `interfaces`.

Comitup uses the default dynamically discovered Wi-Fi device, without assuming a
hardware interface name. If multiple adapters are installed, select the AP-capable
one using `primary_wifi_device` in `/etc/comitup.conf` when necessary. Automatic
multi-radio routing is disabled. No adapter or failed AP capability checks leave
Comitup inactive rather than in a restart loop. After plugging in an adapter,
reboot, or run `sudo systemctl start comitup` once NetworkManager detects it.
Use `sudo comitup --check`, `nmcli device`, and `/var/log/comitup.log` to diagnose
firmware, driver, radio-blocking and management problems. Configure your actual
regulatory country where required; this profile does not guess it from locale.

## Installer firmware versus installed firmware

The preseed enables firmware loading and the non-free-firmware repository. Official
Debian 13 netinst media includes distributable firmware for installer discovery.
The additional packages are installed into the target for later adapter changes.
The current USB workflow still needs Internet access and is not an offline image.
The stock iPXE netboot initrd may lack firmware needed to fetch the preseed: use
wired networking with a supported driver or prepare a matched installer initrd
including Debian's firmware archive. Target package installation cannot solve this
initial bootstrapping problem.

## Validation

See the recorded VM results below. Physical Wi-Fi, regulatory behavior, adapter
hot-plug, and a fresh full installation of the expanded profile still need testing.
The earlier user-reported physical UEFI result covers the base installer only.

## Sources

- [Debian preseed firmware options](https://www.debian.org/releases/trixie/amd64/apbs04.en.html)
- [Debian netboot firmware](https://wiki.debian.org/DebianInstaller/NetbootFirmware)
- [Comitup installation](https://davesteele.github.io/comitup/)
- [Debian Comitup configuration](https://manpages.debian.org/trixie/comitup/comitup-conf.5.en.html)

### Disposable nested-KVM guest, 2026-10-22

A new qcow2 overlay of the previously validated HamClock guest was used; host
networking and physical disks were untouched. Debian installed Comitup 1.43-1 and
all seven requested firmware packages (20250410-2). After reboot with no Wi-Fi,
Ethernet DHCP, password SSH and the HamClock user service remained working;
Comitup reported `inactive` with `Result=exec-condition`, not failed/restarting.

Linux `mac80211_hwsim` provided two simulated radios. One radio remained under
NetworkManager/Comitup; the other was moved into a network namespace to act as an
independent client. WPA association with the configured password succeeded, the
client received a DHCP lease (10.41.0.106), and an HTTP request over the simulated
radio returned the Comitup setup page with status 200. The client used an explicit
address for the HTTP check; DHCP acquisition was tested separately with `udhcpc`.

The second radio was then used as a simulated WPA2 upstream AP with hostapd and
DHCP. Submitting credentials to Comitup's actual `/connect` form endpoint returned
the confirmation page. NetworkManager connected the first radio to
`HamClock-VM-Test`, saved the supplied password, and could ping the upstream AP.
Comitup reached CONNECTED and stopped its web service; Ethernet and HamClock stayed
active. This uses an isolated test network, not an Internet Wi-Fi uplink.

An initial hotspot name identical to the system hostname caused Avahi record
errors. The final default appends `-setup`; the subsequent hotspot logs no longer
contained those errors. Direct-IP portal access is the documented path; automatic
phone captive-portal detection and mDNS name resolution have not been established.
Rerunning the final installation script preserved an operator comment in the
Comitup configuration. The generated preseed embeds the exact Wi-Fi script; all
five local regression tests and ShellCheck pass. This is a guest upgrade test,
not a fresh installer or physical Wi-Fi hardware test. Firmware loading by a real
radio, saved-network behavior across power cycles, network-loss recovery, adapters
without AP support and multi-adapter selection remain in the hardware matrix.
