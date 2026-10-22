# HamClock installation and startup

The shared preseed runs `configure-target.sh`, then `install-hamclock.sh` inside
the installed Debian target. Both script bodies are embedded in the generated
preseed. The second stage fetches and verifies HamClock source, builds it as the
unprivileged `hamclock` user with two compiler jobs, installs it, and configures
startup at the next XFCE login. Build failures stop the late command and must not
be treated as a successful HamClock installation.

## Source and defaults

- Source: https://hamclock.com/ham/HamClock/ESPHamClock.zip
- Observed source version: **4.27** (not a claim that this is the latest release).
- Pinned SHA256: `b751226742033ad88fa900980af079ae99e01eb1c37cbbf6a6c3c91af7655deb`.
- Build target: `hamclock-800x480`, the conservative display-size default.
- Local patch/build ID: `4.27-x11-800x480-monotonic-v1`. The verified source is
  patched before compilation so elapsed timers use `CLOCK_MONOTONIC`.
- Launch: `/usr/local/bin/hamclock -b hamclock.com:80 -f on -d "$HOME/.hamclock"`.
- Backend and X11 build guidance: [maintainer build guide](https://hamclock.com/byo.html).

The archive URL is mutable. If the publisher changes it, installation deliberately
fails checksum verification until a reviewed source/hash update is committed.
HTTPS and the recorded hash protect transport and repeatability; the hash is our
observed source pin, not an upstream detached signature. Upstream's MIT license
is installed with the application. Backend availability and data correctness are
outside this installer. The upstream REST/live-view ports (8080–8082) retain their
normal defaults; this change does not add authentication or a firewall for them.

The native drawing size is 800×480, with fullscreen enabled; larger displays can
have borders. First launch opens HamClock's own station setup. Enter your callsign
and location and select Done. No callsign, location or API credentials are baked
into the installer. Later installs preserve `~/.hamclock` and the machine hostname.
HamClock's own in-app update path is not part of the tested installation workflow.

## Installed files and behavior

- `/usr/local/lib/hamclock/hamclock-800x480`: compiled application, root-owned.
- `/usr/local/bin/hamclock`: command wrapper.
- `/usr/local/bin/hamclock-session`: imports the actual X display/auth environment
  into the user's service manager and starts the service.
- `/usr/local/bin/hamclock-kiosk`: disables X screen blanking/DPMS where supported,
  then runs HamClock with the configured backend and fullscreen options.
- `/etc/systemd/user/hamclock.service`: restart on failure after 10 seconds, limited
  to five starts in two minutes. An intentional normal exit leaves the desktop usable.
- `/home/hamclock/.config/autostart/hamclock.desktop`: XFCE session entry.
- `/usr/local/share/doc/hamclock/LICENSE` and `/usr/local/share/man/man1/hamclock.1`.
- `/var/lib/hamclock-installer/hamclock-source.sha256` , `hamclock-build-id` and `hamclock-profile`: success
  markers. These are separate from the base-OS profile marker.

No root graphical service or hard-coded display number is used. A systemd user
service starts only once even if the desktop launcher is invoked again. On an
upgrade, a matching source marker and existing executable avoid rebuilding;
the patch build ID also participates in cache validation. Replacement builds are
installed through a temporary binary and rename. Concurrent
installs are rejected with a lock. Build dependencies remain installed.

The X blanking commands do not replace every XFCE power-management setting;
physical display sleep, locking and suspend still need a long-duration test.

## Add HamClock to an existing base installation

Copy the reviewed `scripts/install-hamclock.sh` onto the existing installer-created
computer, then run:

```sh
sudo sh install-hamclock.sh
sudo reboot
```

It installs missing dependencies and builds HamClock. No disk repartitioning or
OS reinstall is needed. For a fresh installation, rebuild/write the updated ISO
and use the normal installer flow; the previous base-only ISO does not include
this stage. Source and dependency downloads need internet access and the build
adds several minutes to installation.

From a terminal logged in as `hamclock`, use:

```sh
systemctl --user status hamclock.service
journalctl --user -u hamclock.service
systemctl --user stop hamclock.service
systemctl --user restart hamclock.service
```

To disable future automatic starts, remove or rename
`~/.config/autostart/hamclock.desktop` and stop the service. Running the installer
again restores that autostart entry. App diagnostics/configuration live under
`~/.hamclock`; retain those files when troubleshooting.

## Validation

Tested in a disposable QCOW2 overlay of the previously validated Debian 13 amd64
XFCE guest (nested KVM, two vCPUs, 4096 MiB RAM). The base disk was not modified.
The script installed missing build dependencies, verified the source pin, compiled
and installed HamClock, and `hamclock -v` returned 4.27. A repeat install preserved
the compiled binary checksum. The final build also records the local patch ID,
so a cached unpatched executable cannot bypass the timer fix.

The first startup test exposed a `reset-failed` call on a unit not loaded yet.
The launcher now resets state only when `is-failed` succeeds; a regression test
covers both fresh and failed-unit states. The corrected launcher started HamClock
fullscreen, displaying its station setup. A placeholder `N0CALL` and default test
coordinates were used only in the disposable guest, not in installer defaults.

After a real guest reboot, XFCE automatically started the corrected service
without a manual command. It was active with `NRestarts=0`, retained the station
setup, and the system hostname stayed `hamclock-a5b4c`.

A forced SIGKILL was followed by a new application PID and `NRestarts=1` while the
service returned to active. The local `get_sys.txt` endpoint then reported version
4.27, 800×480 and backend `hamclock.com:80`. A bad-source fixture was rejected with
an explicit checksum error and left the installed executable unchanged.

A further reboot reproduced an upstream timer defect: `millis()` used
`gettimeofday()`, and a boot-time wall-clock correction produced `dt = -373` inside
`wdDelay(100)`. Conversion to an unsigned sleep argument stalled the Ready screen
for an extended period. A debugger located the stalled delay. The installer now
applies a small local patch to use thread-safe initialization and
`CLOCK_MONOTONIC` for elapsed milliseconds, retaining 32-bit wraparound semantics.
A compiled regression test checks monotonic time selection, subsecond-boundary
arithmetic and wraparound. The patched build reached the full dashboard. Moving
the guest wall clock backward by two seconds left the same process responsive
to its status endpoint; guest NTP synchronization was restored after the test.
This patch does not replace UTC/NTP timekeeping.

This is a real application build and guest-upgrade/session test. A complete fresh
Debian installation using the extended late command has not yet been rerun, and
this HamClock stage has not been tested on the user's physical UEFI hardware.
The earlier physical UEFI success applies to the base-only installer. iPXE,
Secure Boot, a long unattended run, power management and backend outage recovery
remain separate acceptance tests.
