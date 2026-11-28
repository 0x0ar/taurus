#!/usr/bin/env bash
# Regenerate every logo derivative from design/bull.svg (run from anywhere).
set -euo pipefail
cd "$(dirname "$0")/.."
G='#00E676'
python3 -I design/trace_line.py design/source_line_bull.png 0 0 330 300 design/line_bull.json 0 >/dev/null
python3 -I design/trace_line.py design/source_line_bull.png 0 0 330 300 design/line_bull_bold.json 2 >/dev/null
python3 -I design/make_bull.py >/dev/null
python3 -I design/make_logo.py
( cd design && python3 -I gen_banner.py )
cp design/bull.svg src/assets/logo.svg
# Website logos. The small icon (navbar, footer mask, favicons) is the bull alone;
# the hero draws the layers in src/assets/logo-*.svg itself (design/make_logo.py
# has already generated them above).
cp design/logo_icon.svg website/static/img/logo.svg
sed "s/#000000/$G/" design/logo_icon.svg > website/static/img/logo-dark.svg
sed "s/#000000/#00a152/" design/logo_icon.svg > website/static/img/logo-light.svg
mkdir -p website/static/img/logo-layers
for n in base light dark bull; do cp src/assets/logo-$n.svg website/static/img/logo-layers/$n.svg; done
BOLD="$(mktemp -d)"; sed "s/#000000/$G/" design/bull_bold.svg > "$BOLD/bold.svg"
sed "s/#000000/$G/" design/logo_icon.svg > "$BOLD/icon.svg"
sed "s/#000000/$G/" design/bull.svg > "$BOLD/bull-green.svg"
rsvg-convert -w 512 -h 512 website/static/img/logo-dark.svg -o website/static/img/logo.png
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for s in 48 192 180; do
  rsvg-convert -w $((s*90/100)) -h $((s*90/100)) "$BOLD/icon.svg" -o "$tmp/f.png"
  magick -size ${s}x${s} xc:black "$tmp/f.png" -gravity center -composite -depth 8 PNG24:"$tmp/f$s.png"
done
cp "$tmp/f48.png" website/static/favicon-48.png
cp "$tmp/f192.png" website/static/favicon-192.png
cp "$tmp/f180.png" website/static/apple-touch-icon.png
magick "$tmp/f48.png" \( "$tmp/f192.png" -resize 32x32 \) \( "$tmp/f192.png" -resize 16x16 \) website/static/favicon.ico
rsvg-convert -w 256 -h 256 "$BOLD/bull-green.svg" -o "$tmp/i.png"
magick -size 256x272 xc:none "$tmp/i.png" -gravity center -composite PNG32:install/assets/logo-installer.png
rsvg-convert -w 40 -h 40 "$BOLD/bold.svg" -o "$tmp/p.png"
magick -size 40x44 xc:none "$tmp/p.png" -gravity center -composite PNG32:src/assets/logo-pixel.png
magick src/assets/logo-pixel.png -alpha extract -depth 8 txt:- | grep -v '^#' | awk -F'[,: ()]+' '{print $1" "$2" "$3}' > "$tmp/alpha.txt"
python3 -I - "$tmp/alpha.txt" <<'PY'
import sys
g = [['.'] * 40 for _ in range(44)]
for line in open(sys.argv[1]):
    x, y, v = map(int, line.split())
    if v >= 100:
        t = y / 43
        g[y][x] = 'W' if t < 0.12 else 'H' if t < 0.3 else 'B' if t < 0.62 else 'M' if t < 0.85 else 'S'
rows = ['    "' + ''.join(r) + '",' for r in g]
p = 'install/logo_pixel.py'
s = open(p).read()
a = s.index('LOGO_PIXEL_GRID = (')
b = s.index('\n)\n', a) + 3
open(p, 'w').write(s[:a] + 'LOGO_PIXEL_GRID = (\n' + '\n'.join(rows) + '\n)\n' + s[b:])
PY
python3 -m py_compile install/logo_pixel.py
rsvg-convert design/banner.svg -o design/banner.png
rsvg-convert design/social.svg -o design/social.png
cp design/banner.png docs/assets/banner.png
magick design/social.png -quality 90 website/static/img/social-card.jpg
for t in amber blue olive violet; do
  magick design/banner.png -quality 85 "website/static/img/banners/banner-$t.webp"
  magick design/banner.png -resize 960x -quality 85 "website/static/img/banners/banner-$t-960.webp"
done
python3 -I design/sync_mascot.py
echo "assets regenerated"
