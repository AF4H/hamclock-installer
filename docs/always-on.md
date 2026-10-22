# Always-on desktop

The installer disables automatic system sleep, screen blanking, and password
locking for the HamClock appliance. XFCE power settings apply on both mains and
battery. The normal account password, sudo and SSH authentication are unchanged.

For an existing installation, copy `scripts/configure-desktop.sh` onto the target,
run `sudo sh configure-desktop.sh`, and reboot once. It applies settings immediately
when the HamClock graphical user service manager is available; login applies them
again. It stops existing Light Locker/XScreensaver processes for `hamclock` and
suppresses their standard autostart entries. It also disables XFCE Screensaver's
idle and lock settings if that component is installed later.

The policy uses a per-user XFCE autostart helper and the running xfconf settings
service. It does not overwrite live user settings files. Systemd sleep, suspend,
hibernate, hybrid-sleep and suspend-then-hibernate targets are masked; logind idle
and lid actions are ignored. Reboot applies the logind changes without restarting
logind in a live session. This is an intentional always-on appliance policy,
including on laptops; the power button/shutdown behavior is preserved.

To restore sleep later, remove `/etc/systemd/logind.conf.d/50-hamclock.conf`,
unmask the five sleep targets, remove
`~/.config/autostart/hamclock-desktop-settings.desktop`, and select the desired
power and locking settings in XFCE. Remove the two `Hidden=true` locker autostart
overrides if restoring those applications. Then reboot.

## Validation, 2026-10-22

Applied the standalone script to the disposable Debian/XFCE VM used for Wi-Fi
integration. Its installed locker was Light Locker 1.8.0; power manager was 4.20.0.
The live update completed successfully. Actual xfconf queries showed idle timeouts
zero on AC/battery, DPMS disabled, presentation mode on, lid actions ignored and
sleep locking off. Screensaver activation/locking settings were false. `xset q`
reported timeout/cycle zero, no preferred blanking and DPMS disabled. Light Locker
was no longer running. A suspend request was rejected and all five targets reported
masked. After reboot and XFCE autostart completion, HamClock was active, Light Locker
remained absent, the idle/lock settings persisted, X screen timeout was zero, DPMS
was disabled, and all five sleep targets remained masked.

This checks configuration and guest behavior; it does not establish physical
monitor firmware settings, laptop firmware behavior or a long-duration idle soak.
The complete expanded ISO still needs a fresh full installation test.

References for the property names and values:
[XFCE power manager settings](https://github.com/xfce-mirror/xfce4-power-manager/blob/xfce4-power-manager-4.20.0/common/xfpm-config.h),
[XFCE screensaver settings](https://github.com/xfce-mirror/xfce4-screensaver/blob/xfce4-screensaver-4.18.3/src/gs-prefs.h).
