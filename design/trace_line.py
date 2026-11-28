#!/usr/bin/env python3
"""Vectorise a dark-on-light line drawing into a single SVG path (no external tracer).

Pipeline: ImageMagick crops/upsamples/blurs the source to a grey PGM, marching
squares extracts sub-pixel contours at mid-grey, Douglas-Peucker simplifies them
and Catmull-Rom splines turn them into cubic Beziers. The result is fitted into
the 270.93 logo viewBox.

usage: trace_line.py SRC.jpg X Y W H OUT.json [grow_px]
  X Y W H   crop box in the source image
  grow_px   thicken the strokes by this many source pixels (default 0)
"""
import json
import math
import subprocess
import sys

VB = 270.93333
SCALE = 3          # upsampling factor before tracing
LEVEL = 128.0


def load_pgm(src, x, y, w, h, grow):
    cmd = ["magick", src, "-crop", f"{w}x{h}+{x}+{y}", "+repage", "-colorspace", "Gray",
           "-resize", f"{SCALE * 100}%", "-blur", "0x1.1"]
    if grow:
        cmd += ["-morphology", "Erode", f"Disk:{grow * SCALE}"]  # erode light = grow dark
    cmd += ["-compress", "none", "pgm:-"]
    data = subprocess.run(cmd, capture_output=True, check=True).stdout.split()
    assert data[0] == b"P2"
    W, H, _ = int(data[1]), int(data[2]), int(data[3])
    vals = list(map(int, data[4:]))
    return W, H, [vals[r * W:(r + 1) * W] for r in range(H)]


def contours(g, W, H):
    """Marching squares on 'dark' (< LEVEL) with linear interpolation; returns closed loops."""
    def interp(p0, v0, p1, v1):
        t = (LEVEL - v0) / (v1 - v0) if v1 != v0 else 0.5
        return (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)

    segs = {}
    def add(a, b):
        segs.setdefault(a, []).append(b)
        segs.setdefault(b, []).append(a)

    key = lambda p: (round(p[0], 3), round(p[1], 3))
    for y in range(H - 1):
        row, nxt = g[y], g[y + 1]
        for x in range(W - 1):
            v = (row[x], row[x + 1], nxt[x + 1], nxt[x])  # tl tr br bl
            idx = (v[0] < LEVEL) | ((v[1] < LEVEL) << 1) | ((v[2] < LEVEL) << 2) | ((v[3] < LEVEL) << 3)
            if idx in (0, 15):
                continue
            pts = ((x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1))
            e = {
                0: interp(pts[0], v[0], pts[1], v[1]),   # top
                1: interp(pts[1], v[1], pts[2], v[2]),   # right
                2: interp(pts[3], v[3], pts[2], v[2]),   # bottom
                3: interp(pts[0], v[0], pts[3], v[3]),   # left
            }
            table = {
                1: [(3, 0)], 2: [(0, 1)], 3: [(3, 1)], 4: [(1, 2)], 5: [(3, 0), (1, 2)],
                6: [(0, 2)], 7: [(3, 2)], 8: [(2, 3)], 9: [(0, 2)], 10: [(0, 1), (2, 3)],
                11: [(1, 2)], 12: [(1, 3)], 13: [(0, 1)], 14: [(3, 0)],
            }
            for a, b in table[idx]:
                add(key(e[a]), key(e[b]))

    loops, seen = [], set()
    for start in list(segs):
        if start in seen:
            continue
        loop, cur, prev = [start], start, None
        seen.add(start)
        while True:
            nbrs = [n for n in segs[cur] if n != prev]
            nxt = None
            for n in nbrs:
                if n not in seen or n == start:
                    nxt = n
                    break
            if nxt is None or nxt == start:
                break
            seen.add(nxt)
            loop.append(nxt)
            prev, cur = cur, nxt
        if len(loop) > 8:
            loops.append(loop)
    return loops


def dp(points, eps):
    if len(points) < 3:
        return points
    (x1, y1), (x2, y2) = points[0], points[-1]
    dx, dy = x2 - x1, y2 - y1
    norm = math.hypot(dx, dy) or 1e-9
    best, idx = 0.0, 0
    for i in range(1, len(points) - 1):
        d = abs(dy * points[i][0] - dx * points[i][1] + x2 * y1 - y2 * x1) / norm
        if d > best:
            best, idx = d, i
    if best > eps:
        return dp(points[:idx + 1], eps)[:-1] + dp(points[idx:], eps)
    return [points[0], points[-1]]


def to_path(loop, tx):
    # a closed loop has coincident ends, so split it at the farthest point first
    far = max(range(len(loop)), key=lambda i: (loop[i][0] - loop[0][0]) ** 2 + (loop[i][1] - loop[0][1]) ** 2)
    a, b = loop[:far + 1], loop[far:] + [loop[0]]
    pts = dp(a, 0.9)[:-1] + dp(b, 0.9)[:-1]
    n = len(pts)
    if n < 4:
        return ""
    P = [tx(p) for p in pts]
    d = [f"M{P[0][0]:.1f} {P[0][1]:.1f}"]
    for i in range(n):
        p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f"C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}")
    return " ".join(d) + " Z"


def main():
    src, x, y, w, h, out = sys.argv[1], *map(int, sys.argv[2:6]), sys.argv[6]
    grow = int(sys.argv[7]) if len(sys.argv) > 7 else 0
    W, H, g = load_pgm(src, x, y, w, h, grow)
    loops = contours(g, W, H)
    xs = [p[0] for l in loops for p in l]
    ys = [p[1] for l in loops for p in l]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    s = (VB * 0.84) / max(x1 - x0, y1 - y0)
    ox = (VB - (x1 - x0) * s) / 2 - x0 * s
    oy = (VB - (y1 - y0) * s) / 2 - y0 * s
    tx = lambda p: (p[0] * s + ox, p[1] * s + oy)
    path = " ".join(t for t in (to_path(l, tx) for l in loops) if t)
    json.dump({"path": path, "loops": len(loops)}, open(out, "w"))
    print(f"{len(loops)} contours, path {len(path)} chars")


if __name__ == "__main__":
    main()
