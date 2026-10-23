# kindle-dash-pw3

A low-power, wall-mounted e-ink dashboard for the **Kindle Paperwhite 3** on a modern
(KindleModding / Universal Hotfix) jailbreak. Fork of
[pascalw/kindle-dash](https://github.com/pascalw/kindle-dash), ported and hardened for this device.

The Kindle wakes up on a schedule via the RTC alarm, turns Wi-Fi on, gets a PNG, draws it, turns
Wi-Fi off and suspends to RAM again. It does **not** render anything itself. The image can come from:

- a **file on the Kindle**,
- any **web server**, e.g. a self-hosted one on your LAN (plain HTTP is fine),
- or **anything else** you script in `local/fetch-dashboard.sh`.

See [IMAGE-SOURCES.md](./IMAGE-SOURCES.md) for the options and the image format (1072x1448, 8-bit grey).

## Tested on

| | |
|---|---|
| Device | Kindle Paperwhite 3 (2015, Wi-Fi, "Muscat on Wario", i.MX6 SoloLite), 1072x1448, 300 ppi, 16 greys |
| Firmware | 5.11.1.1 (armel userland) |
| Jailbreak | KindleModding Universal Hotfix + KPM + scriptlets. **No KUAL, MRPI or USBNetwork needed.** |
| Access | SSH via KOReader's built-in SSH server (dropbear, port 2222) |

Other Kindles may work by changing `RTC` and `BACKLIGHT` at the top of `src/dash.sh`, but only the
PW3 has been tested.

## What changed compared to upstream

- `stop framework` / `start framework` (upstart) instead of `/etc/init.d/framework`, which doesn't exist on 5.x.
- RTC wake via `/sys/class/rtc/rtc1/wakealarm`: absolute epoch, cleared before every write, and
  **never suspends unless the alarm reads back as set**.
- Wi-Fi is switched **off** while suspended and back on at wake-up, then waits for `wifid cmState = CONNECTED`.
- Frontlight **really** off: `flIntensity 0` still leaves the LED at 1/4095, so the driver is also set to 0 at every wake.
- Clean exit: a `STOP` file (checked at every wake) or `SIGTERM` restores everything and restarts the stock UI.
- Doesn't suspend while on USB/charging (keeps refreshing with Wi-Fi on), so plugging in is the "maintenance mode".
- Schedule as simple settings: interval in minutes + active hours + timezone, with a sleep screen at night.
- Uses the system `curl` (TLS 1.2 with certificate checks) instead of a bundled `xh`; sends `X-Kindle-Battery`.
- Starts from the Kindle library through scriptlets, with no KUAL.
- One line per refresh in `battery.log` (timestamp, battery %, fetch result, seconds with Wi-Fi on).
- Native 1072x1448 sleep screen and test card.

## Install

Prerequisites: jailbroken PW3 with Wi-Fi configured, KOReader with its SSH server enabled and your
SSH key installed.

```sh
make dist                      # fetches upstream's prebuilt static next-wakeup, copies src/ to dist/
make deploy KINDLE=<kindle-ip>   # copies dist/ to /mnt/us/dashboard (keeps an existing local/env.sh)
                               # and the scriptlets to /mnt/us/documents
```

No SSH? Copy `dist/` to `dashboard/` and `scriptlets/*` to `documents/` on the Kindle's USB drive.

Two "books" appear in the library:

- **Dashboard Test**: one fetch and draw, no suspend, stock UI keeps running. Log: `logs/test.log`.
- **Start Dashboard**: starts the loop, fully detached. Log: `logs/dash.log`.

Exit KOReader and unplug USB before tapping **Start Dashboard**.

## Configure

Edit `/mnt/us/dashboard/local/env.sh`. It takes effect at the next start.

```sh
DASH_URL="http://192.168.1.10/dash.png"  # web server, or a local path: /mnt/us/dashboard/my.png
INTERVAL_MINUTES=15        # must divide 60, or be 60
ACTIVE_HOURS="7-22"        # local hours that refresh (cron hour field); outside: sleep screen until morning
TIMEZONE="Europe/Rome"     # the device clock stays UTC
#REFRESH_SCHEDULE="*/30 7-22 * * MON-FRI"   # full cron override
```

## Stop / recover

- **Stop:** plug in USB (it stays awake with Wi-Fi on within one interval), then
  `ssh -p 2222 root@KINDLE sh /mnt/us/dashboard/stop.sh`. The stock UI comes back.
- **Recover from anything:** hold the power button ~40 s. Nothing autostarts at boot, so the
  device comes back to the normal UI.

## Gotchas found along the way

- On this jailbreak any `.sh` in `documents/` runs as root when tapped. Without `# DontUseFBInk` the
  launcher clears the screen and prints the script's output over your image.
- Deleting a scriptlet doesn't always remove it from the library; tapping the leftover gives a blank
  screen. `lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home` brings back the home screen.
- Never create `/mnt/us/DONT_START_FRAMEWORK`: the stock UI won't come up after a reboot.
- The Kindle firewall drops ICMP: ping says nothing about whether it's awake.
- The stock screensaver kicks in after ~10 min idle and turns Wi-Fi off, dropping SSH.
- `curl` on this firmware has no `file://` support; busybox `wget` doesn't verify certificates.
- `pgrep -f` over SSH matches the SSH command itself. Use the pid file.

## Credits

- [pascalw/kindle-dash](https://github.com/pascalw/kindle-dash) (MIT), which this is forked from,
  including the `next-wakeup` scheduler.
- [davidhampgonsalves/life-dashboard](https://github.com/davidhampgonsalves/life-dashboard) for the original idea.
- [KindleModding](https://kindlemodding.org/) for the jailbreak, KPM and scriptlets.
