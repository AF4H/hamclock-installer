# First-run station defaults

New HamClock settings start with callsign **N0CALL**, latitude **33.919° N** and
longitude **83.998° W** (signed longitude -83.998). The corresponding Maidenhead
grid is **EM83aw**. Setup remains editable; the profile does not suppress the
first-run setup screen or overwrite a configured station.

`configure-defaults.sh` installs a helper and runs it as the hamclock user. It
creates a private EEPROM file only when neither `.hamclock/eeprom` nor the legacy
`.rpihamclock_eeprom` exists. The kiosk launcher also calls the helper so a new
settings directory receives the same defaults. Existing files, including empty
or customized files, are preserved. It never edits a live station's EEPROM.

The seed uses HamClock's sparse address/byte text format and the pinned 4.27
amd64 layout: NV_BASE 55, cookie 0x5A, lat/lng float cookies at 94/99, callsign at
239 (12 bytes) and DE grid at 534 (7 bytes). The source archive's `nvram.cpp`,
`nvramsize.h`, `nvramlen.h` and EEPROM implementation were inspected to derive
these values. The helper refuses a new seed when the installed archive checksum
marker differs from the pinned binary release. A future binary/layout change
requires revisiting this compatibility guard.

## Validation

Twenty-seven local tests cover seed coordinates/callsign/grid and private mode,
repeat execution, existing/legacy station preservation, unknown binary rejection,
profile ordering/preservation and the previous installer regressions. The pinned
source's own Maidenhead test converted the requested coordinates to EM83aw.
A disposable guest launched the actual static HamClock binary with a fresh
isolated EEPROM; its DE status API reported N0CALL, EM83aw and the expected rounded
latitude/longitude. Existing guest and physical station settings were preserved.

Real NetworkManager offline serialization passed for first creation and repeat
updates; real Comitup candidate selection returned AF4H followed by FieldLink.
On the supplied physical machine, updating presets kept the active connection UUID
unchanged and HamClock's restart count at zero. Radio association with FieldLink
was not exercised; these checks verify saved settings and selection order.

The rebuilt field-defaults ISO has SHA256
`6882cf515039e6798477fe231d74055bfb874e7bba7bfb786e5f4f9f65d16200`.
Its extracted preseed matched the reviewed generator. This final image has not
yet undergone a new full installation; the runtime checks used guest upgrades,
an isolated first-run settings directory, and updates to an existing physical
installation.
