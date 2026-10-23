# Image sources and format

kindle-dash-pw3 only displays images: something else makes them. This page covers where images can
come from and what they must look like.

## Where images come from

Set `DASH_URL` in `local/env.sh`.

### 1. A file on the Kindle

```sh
DASH_URL="/mnt/us/dashboard/my-image.png"
```

A plain path is copied. Put the file there over USB or SSH and it's shown at every refresh. Useful
for a static sign, or for testing (`src/test.png` ships as the default). Wi-Fi still cycles on each
refresh, so battery numbers match a networked setup.

### 2. A web server (self-hosted or not)

```sh
DASH_URL="http://192.168.1.10:8080/dash.png"     # plain HTTP on your LAN is fine
DASH_URL="https://dash.example.org/dash.png"
```

Anything that answers a `GET` with a PNG works: nginx or `python3 -m http.server` serving a file a
cron job regenerates, Home Assistant, a Raspberry Pi taking screenshots of a web page, a hosted service.

The request:

```
GET <DASH_URL>
X-Kindle-Battery: 84          # battery level 0-100, use it or ignore it
```

| Response | Effect |
|---|---|
| `200` + PNG body | drawn on screen |
| anything else, or no answer within 30 s | previous image stays on screen; logged as `fetch=fail(<curl exit code>)` |

HTTPS limits of this firmware (`curl` 7.61 + OpenSSL 1.0.2):

- **TLS 1.2 max.** Servers or CDNs configured as TLS 1.3-only won't work.
- Certificates are checked against a 2019 CA bundle. Let's Encrypt (ISRG Root X1) and the big public
  CAs are in it. **Self-signed certificates fail**: use plain HTTP on the LAN, or a Let's Encrypt cert.
- Wi-Fi is on only during the refresh, so a fast response saves battery.

### 3. Anything else: edit `local/fetch-dashboard.sh`

The script receives one argument, the path to write the PNG to, and must exit `0` on success. Replace
it to pull from an authenticated API, try a fallback, pick a random file from a folder, etc. A non-zero
exit leaves the previous image on screen.

## Image format

- **1072 x 1448 px**, portrait. `eips` draws 1:1 from the top-left corner and never scales.
- **8-bit greyscale** PNG (colour type 0), **no alpha**.
- The panel shows **16 grey levels** (0x00, 0x11, ... 0xFF). Other values get rounded or dithered.

`src/test.png` (from `tools/make-test-image.sh`) is a reference card with a frame, corner squares and a
16-step grey bar. If it fills the screen edge to edge and every block looks different, your format is right.

Converting any image with ImageMagick (`-posterize 16` snaps to exactly the 16 panel levels):

```sh
magick input.jpg -resize 1072x1448^ -gravity center -extent 1072x1448 \
  -colorspace Gray -dither FloydSteinberg -posterize 16 -depth 8 -define png:color-type=0 dash.png
```

## Refresh behaviour

- Partial refresh normally. A full, flashing refresh every `FULL_DISPLAY_REFRESH_RATE` updates
  (default 4) clears ghosting.
- No fetches outside `ACTIVE_HOURS`: the device shows `sleeping.png` and suspends until the next active hour.
