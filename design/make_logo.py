#!/usr/bin/env python3
"""Generate the Taurus logo.

The logo is a bull line on a "puddle" of cross-hatching: large diagonal dashes
that break up and dissolve towards an irregular, implied outline. It is built
in layers so every consumer can tint it with its own palette:

  src/assets/logo-base.svg   scattered fragments (darkest tone)
  src/assets/logo-light.svg  hatch, "/" direction
  src/assets/logo-dark.svg   hatch, "\\" direction
  src/assets/logo-bull.svg   the bull line (checked in, not generated)

All layers share one landscape viewBox (300 x 190) and are drawn in black; the
shell (TaurusLogo.qml) and the website (AnimatedLogo) tint them. This script
also composes the full-colour variants and the small square icon:

  design/logo_dark.svg / logo_light.svg   full colour, for dark / light backgrounds
  design/logo_icon.svg                    the bull alone, square, black (mask)

The hatch is pseudo-random with a fixed seed, so the output is reproducible:
    python3 design/make_logo.py [seed]
"""
import math
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "src" / "assets"
DESIGN = ROOT / "design"

VW, VH = 300.0, 190.0
SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 5

# The bull line is centred on the canvas; these are its size in canvas units.
CX, CY = VW / 2, VH * 0.50
BH = VH * 0.50
BW = BH * 1242 / 1172

# Palette used for the full-colour composites (the shell uses Matugen instead).
PALETTE = {"base": "#157a47", "light": "#2fd37f", "dark": "#1d8f55"}
BULL_DARK_BG, BULL_LIGHT_BG = "#eef1f2", "#0b1a12"


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def build_hatch(seed):
    rng = random.Random(seed)
    ax, ay = 134.0, 84.0
    harm = [(2, .055), (3, .07), (4, .05), (5, .045), (6, .035), (7, .03), (8, .022), (9, .018), (11, .012)]
    ph = [rng.uniform(0, 2 * math.pi) for _ in harm]

    def radius(th):
        return 1 + sum(a * math.cos(k * th + p) for (k, a), p in zip(harm, ph))

    mx = max(radius(t / 360 * 2 * math.pi) for t in range(360))
    ax /= mx ** 0.5
    ay /= mx ** 0.5

    def edge(x, y):  # > 0 inside the implied outline, < 0 outside
        u, v = (x - CX) / ax, (y - CY) / ay
        return 1 - math.hypot(u, v) / radius(math.atan2(v, u))

    def clear(x, y):  # empty space around the bull
        return smooth(0.58, 1.05, math.hypot((x - CX) / (BW * 0.56), (y - CY) / (BH * 0.58)))

    def width(x, y, wmax=1.9):
        return wmax * clear(x, y) * (0.45 + 0.55 * smooth(0.0, 0.30, edge(x, y)))

    def frag(x, y):
        return 0.10 + 0.80 * (1 - smooth(0.0, 0.5, edge(x, y)))

    def clamp(p):
        return min(VW, max(0, p[0])), min(VH, max(0, p[1]))

    def ribbon(run):
        left = [(x + nx * w / 2, y + ny * w / 2) for x, y, w, nx, ny in run]
        right = [(x - nx * w / 2, y - ny * w / 2) for x, y, w, nx, ny in reversed(run)]
        return " ".join("%.2f,%.2f" % clamp(p) for p in left + right)

    def family(theta, spacing, offset):
        d = (math.cos(theta), math.sin(theta))
        n = (-d[1], d[0])
        polys = []
        c = -500 + offset
        while c < 500:
            px, py = CX + n[0] * c, CY + n[1] * c
            t = -300.0
            while t < 300:
                x, y = px + d[0] * t, py + d[1] * t
                if edge(x, y) < -0.02:
                    t += 4
                    continue
                fr = frag(x, y)
                th = rng.uniform(0, 0.10)
                dash = rng.uniform(14, 40) * (1 - 0.62 * fr)
                gap = rng.uniform(2.0, 4.5) * (1 + 3.4 * fr ** 1.4)
                run, tt, end = [], t, t + dash
                while tt <= end + 1e-6:
                    xx, yy = px + d[0] * tt, py + d[1] * tt
                    if edge(xx, yy) > th:
                        w = width(xx, yy) * rng.uniform(0.9, 1.1)
                        if w >= 0.2:
                            run.append((xx, yy, w, n[0], n[1]))
                    tt += 2.0
                if len(run) >= 2:
                    polys.append(ribbon(run))
                t = end + gap
            c += spacing
        return polys

    light = family(math.radians(-41), 25.0, 0.0)
    dark = family(math.radians(49), 27.0, 9.0)

    base = []
    for _ in range(2600):
        x, y = rng.uniform(0, VW), rng.uniform(0, VH)
        e = edge(x, y)
        if not (-0.32 < e < 0.10):
            continue
        if rng.random() > 0.16 * (1 - min(1, abs(e + 0.02) / 0.3)):
            continue
        th = math.radians(-41 if rng.random() < 0.5 else 49)
        length, w = rng.uniform(2.5, 7), rng.uniform(0.7, 1.1)
        d = (math.cos(th), math.sin(th))
        n = (-d[1], d[0])
        pts = [(x - d[0] * length / 2 + n[0] * w / 2, y - d[1] * length / 2 + n[1] * w / 2),
               (x + d[0] * length / 2 + n[0] * w / 2, y + d[1] * length / 2 + n[1] * w / 2),
               (x + d[0] * length / 2 - n[0] * w / 2, y + d[1] * length / 2 - n[1] * w / 2),
               (x - d[0] * length / 2 - n[0] * w / 2, y - d[1] * length / 2 - n[1] * w / 2)]
        if all(0 <= q[0] <= VW and 0 <= q[1] <= VH for q in pts):
            base.append(" ".join("%.2f,%.2f" % q for q in pts))
    return {"base": base, "light": light, "dark": dark}


def hatch_field(w, h, focus, zones, scale=2.5, seed=3):
    """Full-bleed variant of the hatch for a w x h canvas (banners).

    The strokes are the same diagonal dashes as the logo, but they cover the whole
    canvas, break up more the further they are from `focus` (cx, cy), and keep
    clear of `zones`: soft ellipses (cx, cy, rx, ry) such as the bull and the text.
    Returns {"base": [...], "light": [...], "dark": [...]} polygon point strings.
    """
    rng = random.Random(seed)
    diag = math.hypot(w, h)
    fx, fy = focus

    def far(x, y):
        return math.hypot(x - fx, y - fy) / (diag * 0.55)

    def clear(x, y):
        c = 1.0
        for zx, zy, rx, ry in zones:
            c *= smooth(0.62, 1.15, math.hypot((x - zx) / rx, (y - zy) / ry))
        return c

    def width(x, y):
        return 1.6 * scale * clear(x, y) * (0.30 + 0.70 * (1 - smooth(0.10, 0.95, far(x, y))))

    def frag(x, y):
        return 0.12 + 0.75 * smooth(0.35, 1.15, far(x, y))

    def clamp(p):
        return min(w, max(0, p[0])), min(h, max(0, p[1]))

    def ribbon(run):
        left = [(x + nx * wd / 2, y + ny * wd / 2) for x, y, wd, nx, ny in run]
        right = [(x - nx * wd / 2, y - ny * wd / 2) for x, y, wd, nx, ny in reversed(run)]
        return " ".join("%.1f,%.1f" % clamp(p) for p in left + right)

    def family(theta, spacing, offset):
        d = (math.cos(theta), math.sin(theta))
        n = (-d[1], d[0])
        polys = []
        c = -diag + offset
        while c < diag:
            px, py = w / 2 + n[0] * c, h / 2 + n[1] * c
            lo, hi = -1e9, 1e9
            for p0, dd, a, b in ((px, d[0], 0, w), (py, d[1], 0, h)):
                if abs(dd) < 1e-9:
                    if p0 < a or p0 > b:
                        lo, hi = 1, 0
                else:
                    t1, t2 = (a - p0) / dd, (b - p0) / dd
                    if t1 > t2:
                        t1, t2 = t2, t1
                    lo, hi = max(lo, t1), min(hi, t2)
            t = lo
            while t < hi:
                x, y = px + d[0] * t, py + d[1] * t
                fr = frag(x, y)
                dash = rng.uniform(14, 40) * scale * (1 - 0.62 * fr)
                gap = rng.uniform(2.0, 4.5) * scale * (1 + 3.4 * fr ** 1.4)
                run, tt, end = [], t, min(hi, t + dash)
                while tt <= end + 1e-6:
                    xx, yy = px + d[0] * tt, py + d[1] * tt
                    wd = width(xx, yy) * rng.uniform(0.9, 1.1)
                    if wd >= 0.2 * scale:
                        run.append((xx, yy, wd, n[0], n[1]))
                    tt += 2.0 * scale
                if len(run) >= 2:
                    polys.append(ribbon(run))
                t = end + gap
            c += spacing
        return polys

    light = family(math.radians(-41), 37.0 * scale, 0.0)
    dark = family(math.radians(49), 40.0 * scale, 13.0 * scale)
    base = []
    for _ in range(int(w * h / 900)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        if rng.random() > 0.55 * frag(x, y) ** 1.6 * smooth(0.55, 1.1, clear(x, y)):
            continue
        th = math.radians(-41 if rng.random() < 0.5 else 49)
        length, wd = rng.uniform(2.5, 7) * scale, rng.uniform(0.7, 1.1) * scale
        d = (math.cos(th), math.sin(th))
        n = (-d[1], d[0])
        pts = [(x - d[0] * length / 2 + n[0] * wd / 2, y - d[1] * length / 2 + n[1] * wd / 2),
               (x + d[0] * length / 2 + n[0] * wd / 2, y + d[1] * length / 2 + n[1] * wd / 2),
               (x + d[0] * length / 2 - n[0] * wd / 2, y + d[1] * length / 2 - n[1] * wd / 2),
               (x - d[0] * length / 2 - n[0] * wd / 2, y - d[1] * length / 2 - n[1] * wd / 2)]
        if all(0 <= q[0] <= w and 0 <= q[1] <= h for q in pts):
            base.append(" ".join("%.1f,%.1f" % q for q in pts))
    return {"base": base, "light": light, "dark": dark}


def layer_svg(body, transform=""):
    tf = f' transform="{transform}"' if transform else ""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="760" viewBox="0 0 {VW:g} {VH:g}">\n'
        "  <title>Taurus</title>\n"
        f'  <g fill="#000000" stroke="none"{tf}>\n{body}\n  </g>\n</svg>\n'
    )


def inner(text):
    """(attributes of the layer group, its markup) from a layer file."""
    m = re.search(r'<g fill="#000000" stroke="none"([^>]*)>\n(.*)\n  </g>\n</svg>', text, re.S)
    return m.group(1), m.group(2)


def compose(colors, viewbox=None):
    vb = viewbox or f"0 0 {VW:g} {VH:g}"
    w, h = (1024, 1024) if viewbox else (1200, 760)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{vb}">', "  <title>Taurus</title>"]
    for name, fill in colors:
        attrs, body = inner((ASSETS / f"logo-{name}.svg").read_text())
        out.append(f'  <g fill="{fill}" stroke="none"{attrs}>\n{body}\n  </g>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    layers = build_hatch(SEED)
    for name, polys in layers.items():
        body = "\n".join(f'    <polygon points="{p}"/>' for p in polys)
        (ASSETS / f"logo-{name}.svg").write_text(layer_svg(body))
    pal = PALETTE
    (DESIGN / "logo_dark.svg").write_text(compose([("base", pal["base"]), ("light", pal["light"]), ("dark", pal["dark"]), ("bull", BULL_DARK_BG)]))
    (DESIGN / "logo_light.svg").write_text(compose([("base", pal["base"]), ("light", pal["light"]), ("dark", pal["dark"]), ("bull", BULL_LIGHT_BG)]))
    half = max(BW, BH) * 0.57
    (DESIGN / "logo_icon.svg").write_text(compose([("bull", "#000000")], viewbox=f"{CX - half:.2f} {CY - half:.2f} {2 * half:.2f} {2 * half:.2f}"))
    print(f"logo generated (seed {SEED}): " + ", ".join(f"{k}={len(v)}" for k, v in layers.items()))


if __name__ == "__main__":
    main()
