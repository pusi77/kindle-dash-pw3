# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [pw3-v0.1.0] - 2026-10-23

Fork for the Kindle Paperwhite 3 on firmware 5.11.1.1 with the KindleModding Universal Hotfix jailbreak.

### Added
- Scriptlets "Start Dashboard" and "Dashboard Test" (library entries; no KUAL needed).
- `dash.sh once`: single fetch + draw, no framework stop, no suspend.
- STOP file and SIGTERM clean exit: restores governor, frontlight, screensaver, Wi-Fi; restarts the framework.
- No suspend while on USB/charging.
- Schedule from `INTERVAL_MINUTES` + `ACTIVE_HOURS` + `TIMEZONE`.
- `battery.log`: one line per refresh with battery %, fetch result, seconds with Wi-Fi on.
- Local file or HTTP(S) image sources; `X-Kindle-Battery` request header; `IMAGE-SOURCES.md`.
- PW3-native 1072x1448 `sleeping.png` and `test.png` (+ `tools/make-test-image.sh`).
- `make deploy` over KOReader's SSH (port 2222).

### Changed
- Framework control via upstart (`stop/start framework`).
- RTC wake via `/sys/class/rtc/rtc1/wakealarm` (absolute epoch, cleared first, verified before suspend).
- Wi-Fi switched off during suspend; readiness from `wifid cmState` instead of pinging.
- Frontlight forced fully off through the backlight driver at every wake.
- Validates `next-wakeup` output (fallback 300 s), sleeps instead of suspending for waits under 15 s.
- Downloads to a temp file and only replaces `dash.png` on success.
- `next-wakeup` taken prebuilt from upstream v1.0.0-beta.4 (`make build-next-wakeup` to rebuild).

### Removed
- Bundled `xh` HTTP client (system `curl` does TLS 1.2 with certificate verification).
- `wait-for-wifi.sh`, KUAL menu.
- Low-battery hook (`local/low-battery.sh`): servers get `X-Kindle-Battery` on every request, and `battery.log` covers local monitoring.
- Kindle 4 leftovers: `example/` (600x800 sample, photo), `docs/tipstricks.md`, `docs/screenshotter` (600x800 Puppeteer/Node 12 renderer).

## [v1.0.0-beta.4] - 2022-07-27

### Changed

- Only call eips if fetch-dashboard succesfully completes
- Ensure a full screen refresh is triggered after wake from sleep
- Build ht from upstream sources, using rusttls instead of vendored openssl
- Replace ht 0.4.0 with xh 0.16.1 (project was renamed)

## [v1.0.0-beta.3] - 2020-02-03

### Changed

- Use 1.1.1.1 as default Wi-Fi test ip
- Use a more standards-compliant cron parser (BREAKING)

### Added

- Add low battery reporting (`local/low-battery.sh`)
- Add debug mode (DEBUG=true start.sh)
- SSH server prerequisite in docs (@julianlam)

### Fixed

- Typos (@jcmiller11, @starcoat)

## [v1.0.0-beta-2] - 2020-01-26

### Removed

- Power state logging

## [v1.0.0-beta-1] - 2020-01-26

Initial release 🎉
