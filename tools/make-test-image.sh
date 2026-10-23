#!/usr/bin/env bash
# Builds a PW3-native 1072x1448 8-bit greyscale test card (default: src/test.png).
# Usage: tools/make-test-image.sh [output.png]   (needs ImageMagick 7 + Noto Sans)
set -euo pipefail
OUT=${1:-"$(dirname "$0")/../src/test.png"}
B=$(fc-match -f '%{file}' "Noto Sans:bold")
R=$(fc-match -f '%{file}' "Noto Sans")

args=(-size 1072x1448 xc:white
  # 1px frame + corner squares: any crop/offset shows up immediately
  -stroke black -strokewidth 1 -fill none -draw "rectangle 0,0 1071,1447" -stroke none
  -fill black
  -draw "rectangle 0,0 40,40" -draw "rectangle 1031,0 1071,40"
  -draw "rectangle 0,1407 40,1447" -draw "rectangle 1031,1407 1071,1447"
  -gravity north
  -font "$B" -pointsize 96 -annotate +0+140 "Kindle Dashboard"
  -font "$R" -pointsize 48 -annotate +0+290 "test image · 1072 × 1448 · 8-bit grey"
  -pointsize 40 -annotate +0+420 "If this fills the screen edge to edge,"
  -annotate +0+480 "your image size is right."
  -pointsize 32 -annotate +0+1120 "16 grey levels: every block should look different"
  -gravity northwest)

# 16 blocks, 0x00..0xFF in 0x11 steps (the PW3's 16 grey levels), 67px each = 1072px
for i in $(seq 0 15); do
  v=$((i * 17))
  args+=(-fill "rgb($v,$v,$v)" -draw "rectangle $((i * 67)),900 $((i * 67 + 66)),1100")
done

# outline so the last (pure white) block is visible
args+=(-fill none -stroke black -strokewidth 1 -draw "rectangle 0,899 1071,1101" -stroke none)

magick "${args[@]}" -alpha off -colorspace Gray -depth 8 -define png:color-type=0 "$OUT"
