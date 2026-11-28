#!/usr/bin/env python3
"""Rewrite the bull art inside the animated shell mascot from design/bull.json.

Updates src/quickshell/reusables/display/Bull.qml (Shape block). The website no
longer has an animated mascot.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
art = json.load(open(os.path.join(HERE, "bull.json")))
parts, eyes = art["parts"], art["eyes"]

# ---- QML
p = os.path.join(ROOT, "src/quickshell/reusables/display/Bull.qml")
s = open(p).read()
a = s.index("            Shape {")
tail = "\n        }\n    }\n}\n"
b = s.rindex(tail)
blk = ["            Shape {", "                anchors.fill: parent",
       "                preferredRendererType: Shape.CurveRenderer", ""]
for d in parts:
    blk += ["                ShapePath {", "                    fillColor: root.color",
            '                    strokeColor: "transparent"',
            "                    fillRule: ShapePath.OddEvenFill",
            f'                    PathSvg {{ path: "{d}" }}', "                }"]
blk.append("                // glowing eye")
for d in eyes:
    blk += ["                ShapePath {",
            "                    fillColor: Qt.rgba(root.eyeColor.r, root.eyeColor.g, root.eyeColor.b, root.eyeGlow)",
            '                    strokeColor: "transparent"',
            f'                    PathSvg {{ path: "{d}" }}', "                }"]
blk.append("            }")
open(p, "w").write(s[:a] + "\n".join(blk) + s[b:])

print("mascot art synced")
