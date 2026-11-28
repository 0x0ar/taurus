#!/usr/bin/env python3
"""Generate files that must ship inside src/ from files that live elsewhere in the repo.

1. The reference guides inside the agent skills, from docs/ (docs/ is not installed).
2. src/assets/settings.default.json, a verbatim copy of config/taurus/settings.json: the curl
   installer copies only bin/ and src/, and `taurus config reset|diff` need the shipped defaults.


docs/ is not installed with Taurus, so the skills carry their own copies. Run this after
editing docs/. `--check` exits 1 when a copy is out of date (used by the test suite).

usage: sync-skill-docs.py [--check]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "src/agents/skills/taurus/references")

SOURCES = {
    "docs/configure/Configure.md": "settings.md",
    "docs/configure/AppTheming.md": "app-theming.md",
    "docs/cli/client.md": "cli.md",
}
for name in ("hyprland", "niri", "sway", "mango", "umbriel"):
    SOURCES[f"docs/configure/compositors/{name}.md"] = f"compositors/{name}.md"


def convert(text, src):
    text = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S)           # docusaurus frontmatter
    text = re.sub(r"^:::(\w+)\[([^\]]*)\]\s*$", r"> **\2**", text, flags=re.M)
    text = re.sub(r"^:::\w+\s*$", "", text, flags=re.M)
    text = re.sub(r"^:::\s*$", "", text, flags=re.M)
    # relative links point into docs/, which is not installed: keep the text only
    text = re.sub(r"\[([^\]]+)\]\((?!https?://|#|mailto:)[^)]*\)", r"\1", text)
    text = re.sub(r"!\[[^\]]*\]\((?!https?://)[^)]*\)\n?", "", text)      # local images
    return f"<!-- Generated from {src} by tools/sync-skill-docs.py. Do not edit. -->\n\n" + text.lstrip("\n")


COPIES = {"config/taurus/settings.json": "src/assets/settings.default.json"}


def main():
    check = "--check" in sys.argv
    stale = []
    for src, dest in COPIES.items():
        out = os.path.join(ROOT, dest)
        want = open(os.path.join(ROOT, src)).read()
        if (open(out).read() if os.path.exists(out) else None) != want:
            stale.append(dest)
            if not check:
                open(out, "w").write(want)
    for src, dest in SOURCES.items():
        out = os.path.join(REF, dest)
        want = convert(open(os.path.join(ROOT, src)).read(), src)
        have = open(out).read() if os.path.exists(out) else None
        if have != want:
            stale.append(dest)
            if not check:
                os.makedirs(os.path.dirname(out), exist_ok=True)
                open(out, "w").write(want)
    if check and stale:
        print("out of date: " + ", ".join(stale) + " (run tools/sync-skill-docs.py)")
        sys.exit(1)
    print(("checked" if check else "synced") + f" {len(SOURCES)} guides and {len(COPIES)} copied file")


main()
