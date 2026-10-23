# Automatic display fitting

The prebuilt native HamClock canvas is 800×480. Fullscreen alone centers those
pixels without enlarging them. At graphical startup, the display stage's fitter
reads the active XRandR mode, computes a logical desktop that fits the entire
canvas, and scales that desktop onto the panel's existing mode. HamClock still
starts with `-f on`; aspect ratio is preserved, with narrow black borders when the
panel proportions differ. This enlarges the existing canvas rather than adding
rendering detail; no binary compilation or extra application download is needed.

For 1366×768, the logical desktop is 854×480; for 1280×800 it is 800×500. Both
preserve the physical display mode and refresh rate. The fitter runs again on
HamClock startup. It requires exactly one active output; multiple active displays
are left unchanged. It does not automatically reconfigure hotplug events while
HamClock is running. Driver rejection restores an unscaled desktop and allows
ordinary fullscreen startup to continue. No saved monitor configuration is edited.

The launcher's display fitter is `/usr/local/bin/hamclock-display`. To return to
an unscaled desktop manually, use the output and native mode reported by
`xrandr --current`, for example:

```sh
xrandr --output eDP-1 --scale 1x1 --panning 0x0 --fb 1366x768
```

## Validation

Twenty-one local tests and ShellCheck pass, including landscape, portrait,
low-resolution and exact-size calculations, multiple-output fallback, and a
rejected transform's rollback. A disposable Xorg/KVM guest at 1280×800 applied
800×500 logical geometry and displayed HamClock's setup screen enlarged across
the display. The same existing guest's root-owned XFCE configuration parent was
repaired; its cached failed xfconfd service also needed restarting before a new
LightDM session succeeded.

On the supplied physical machine, a 1366×768 eDP display accepted 854×480 logical
geometry while retaining the native mode. The running HamClock PID and restart
count remained unchanged during application of the transform; future startup
uses the installed fitter automatically. Touch accuracy after scaling and
multi-monitor operation need separate physical validation. The XFCE ownership
repair restored the real desktop before scaling was applied.
