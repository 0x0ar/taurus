#!/usr/bin/env python3
"""Banner and social card SVGs for Taurus (green on black).

The whole background is the logo's cross-hatch (make_logo.hatch_field): large
diagonal dashes that break up as they get away from the bull and keep clear of
the bull and the text. The bull line comes from src/assets/logo-bull.svg.
"""
import importlib.util
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("make_logo", os.path.join(HERE, "make_logo.py"))
make_logo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_logo)

bull = open(os.path.join(HERE, "..", "src", "assets", "logo-bull.svg")).read()
m = re.search(r'<g fill="#000000" stroke="none"( transform="[^"]*")?>\n(.*)\n  </g>\n</svg>', bull, re.S)
BULL_ATTR, BULL_BODY = m.group(1) or "", m.group(2)
BW, BH = make_logo.BW, make_logo.BH          # bull size in logo units
CX, CY = make_logo.CX, make_logo.CY          # bull centre in logo units

COLORS = {"base": "#157a47", "light": "#2fd37f", "dark": "#1d8f55"}


def banner(w, h, bull_h, bull_cx, tx, ty, fs, fs2, scale):
    k = bull_h / BH
    bull_cy = h / 2
    zones = [
        (bull_cx, bull_cy, BW * k * 0.62, BH * k * 0.64),                      # the bull
        (tx + (w - tx) * 0.42, ty - fs * 0.30, (w - tx) * 0.58, fs * 1.15),    # the text
    ]
    layers = make_logo.hatch_field(w, h, (bull_cx, bull_cy), zones, scale=scale)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
           f'<rect width="{w}" height="{h}" fill="#000"/>']
    for name in ("base", "dark", "light"):
        out.append(f'<g fill="{COLORS[name]}">')
        out += [f'<polygon points="{p}"/>' for p in layers[name]]
        out.append("</g>")
    out.append(f'<g transform="translate({bull_cx},{bull_cy}) scale({k:.4f}) translate({-CX},{-CY})">'
               f'<g fill="#eef1f2" stroke="none"{BULL_ATTR}>\n{BULL_BODY}\n</g></g>')
    out.append(f'<text x="{tx}" y="{ty}" font-family="Noto Sans" font-weight="900" font-size="{fs}" '
               f'letter-spacing="{fs*0.04}" fill="#00E676">TAURUS</text>')
    out.append(f'<text x="{tx+4}" y="{ty+fs2*1.5}" font-family="Noto Sans" font-weight="800" font-size="{fs2}" '
               f'letter-spacing="{fs2*0.2}" fill="#33eb91">A desktop shell built for YOU</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


os.chdir(HERE)
open("banner.svg", "w").write(banner(1920, 845, 470, 400, 760, 470, 150, 38, 2.6))
open("social.svg", "w").write(banner(1200, 630, 330, 255, 500, 350, 105, 26, 1.9))
