#!/usr/bin/env python3
"""Build bull.svg / bull.json (and a bold variant for tiny icons) from the traced line bull.

The traced paths come from trace_line.py (see build_assets.sh). The bull is a single
continuous line drawing facing right. EYE is only used by the animated mascot.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
# almond inside the brow loop, in viewBox units (lit up red by the mascot when charging)
EYE = "M188 135 C194 130 204 130 212 138 C204 141 194 141 188 135 Z"


def write(name, trace):
    path = json.load(open(os.path.join(HERE, trace)))["path"]
    open(os.path.join(HERE, name + ".svg"), "w").write(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 270.93333 270.93333">\n'
        f'  <title>Taurus</title>\n  <g fill="#000000">\n    <path fill-rule="evenodd" d="{path}"/>\n  </g>\n</svg>\n'
    )
    return path


path = write("bull", "line_bull.json")
write("bull_bold", "line_bull_bold.json")
json.dump({"parts": [path], "eyes": [EYE]}, open(os.path.join(HERE, "bull.json"), "w"))
print("bull.svg, bull_bold.svg, bull.json written")
