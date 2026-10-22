# Finding HamClock on the local network

After the machine connects to Wi-Fi or Ethernet, use its persistent hostname with
`.local` appended. For a setup hotspot named `hamclock-abc12-setup`, that is:

- Browser control: `http://hamclock-abc12.local:8081/live.html`
- Read-only browser view: `http://hamclock-abc12.local:8082/live.html`
- SSH: `ssh hamclock@hamclock-abc12.local`

The initial SSH password is `h@mradio`. The host's actual name is also available
with `hostname` on its console. Use each machine's own suffix; there is no shared
`hamclock.local` alias. Browser access uses HamClock's existing live web server,
which starts with its desktop session. Desktop sharing such as VNC/RDP is not
installed by this feature.

The client must support mDNS and be on the same local multicast network. Guest
Wi-Fi isolation, VLAN separation or blocked multicast can prevent `.local` access;
use the machine's IP address in that case. This is local discovery, not an Internet
remote-access service. HamClock's existing unauthenticated live-control interface
is unchanged.

## Implementation and existing installations

Avahi already accompanies Comitup, so the earlier Wi-Fi/always-on image normally
publishes the machine's `.local` address without this update. The installer now
explicitly installs/enables `avahi-daemon`, `avahi-utils` and `libnss-mdns`, and adds
DNS-SD records for SSH (`_ssh._tcp`, port 22) and HamClock (`_http._tcp`, port 8081,
TXT `path=/live.html`). These appear in clients with service browsing support.
The default Avahi configuration follows the system hostname and available network
interfaces; no Wi-Fi device name, IP address or separate hostname is hard-coded.
Existing Avahi configuration is preserved, including any administrator restrictions.

For the earlier installation, copy `scripts/install-mdns.sh` onto the target and
run `sudo sh install-mdns.sh`. No reinstall is needed. The script enables the
service for boot and reloads or starts it on a running system. Complete XML files
are published atomically so Avahi never sees partially written records. Repeat
runs replace the same two service records without creating duplicate files.

From another Linux machine with Avahi utilities, check:

```sh
avahi-resolve -n hamclock-abc12.local
avahi-browse -rt _ssh._tcp
avahi-browse -rt _http._tcp
```

On the target, `systemctl status avahi-daemon`, `getent hosts "$(hostname).local"`
and `journalctl -u avahi-daemon` help diagnose discovery. Do not replace a custom
Avahi configuration blindly if publication was intentionally restricted.

## Validation, 2026-10-22

The existing disposable Debian guest already had Avahi active and resolved its
persistent `hamclock-a5b4c.local` name before this stage was added. After applying
the stage, an independent UDP mDNS client in an isolated network namespace queried
across a newly attached virtual Ethernet link. It received the correct interface
address (192.0.2.1), SSH service/port/hostname, HTTP service/port/hostname and
`path=/live.html` TXT record. A browser-page HTTP request across that link returned
200 and the HamClock live HTML. The client did not use the server's Avahi cache or
D-Bus connection. The first query raced interface discovery and timed out; a query
after Avahi registered the link passed. Discovery can take a few seconds following
connection.

The final script was applied twice successfully. After reboot, the hostname
still resolved, Avahi was active, both service records resolved with the expected
ports/path, and HamClock was active. This tests guest discovery and dynamic interface registration;
it does not establish discovery on every physical Wi-Fi AP, client OS, VLAN or
router. A fresh full installation of the expanded ISO remains untested.

References: [Avahi configuration](https://github.com/avahi/avahi/blob/master/man/avahi-daemon.conf.5.xml.in),
[Avahi service-file format](https://github.com/avahi/avahi/blob/master/man/avahi.service.5.xml.in).
