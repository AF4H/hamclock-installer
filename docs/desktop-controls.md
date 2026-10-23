# Desktop shortcut and native shutdown

Setup installs `/usr/local/share/applications/hamclock.desktop` and an executable,
user-owned `~/Desktop/HamClock.desktop`. Both use `hamclock-session`, which imports
the graphical environment and starts the supervised user service. Reopening the
shortcut reuses a running service instead of creating another HamClock process.
The GLib desktop-launch tools are installed explicitly. At graphical login, only
the managed desktop launcher's checksum is marked trusted when GVFS metadata is
available; XFCE accepts executable launchers when that optional backend is absent.
Its normal trust checks remain enabled.

HamClock 4.27 invokes `/sbin/poweroff` directly for Shutdown computer and falls
back to `/sbin/halt` on failure. The lean image lacked `polkitd`; the unprivileged
service could not complete the logind authorization request. The power stage
installs that daemon and a rule granting the `hamclock` account only these actions:

- `org.freedesktop.login1.power-off`
- `org.freedesktop.login1.power-off-multiple-sessions`

The second action permits shutdown while an SSH or other login is present. The
rule uses the account identity because a systemd user service does not belong to
the active graphical session scope. It grants no general root execution, reboot
or inhibitor-bypass authorization. HamClock's existing in-app confirmation is
unchanged. Setup installs permissions only and never requests shutdown itself.

## Validation

The disposable Xorg/KVM guest verified both power-off authorizations through
`pkcheck`, including from a transient systemd user service. An unrelated `nobody`
process was denied. XFCE's native trust API accepted the desktop launcher; opening
it through `gio launch` started HamClock, and a second opening preserved the PID.
The actual `/sbin/poweroff` request from an unprivileged systemd user service
with SSH connected cleanly powered down the disposable VM. QEMU exited and the
virtual disk passed its consistency check. No root command or sudo was used for
that shutdown.

On the supplied physical machine, both power-off checks and a transient user
service's authorization check passed. The policy daemon was active, the shortcut
was user-owned/executable and XFCE's native API reported it trusted. No physical
shutdown was executed. The new ISO contains the exact generated preseed; its
SHA256 is `1b3dcbb8d05ec98e275fa389ba38e06baa91cf2448951b1dd41a6c22a59868c8`.
A new full installation of this final desktop-controls image remains untested.

References: [XFCE launcher trust API](https://developer.xfce.org/libxfce4util/libxfce4util-GIO-Extensions.html),
HamClock 4.27 `ESPHamClock.cpp` shutdown handler, and the installed Debian logind
policy action definitions. Desktop and power setup are shared by USB, iPXE and
the generated recovery script.
