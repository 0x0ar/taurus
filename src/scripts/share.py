#!/usr/bin/env python3
"""taurus share: export your setup to ONE file, and import someone else's safely.

    taurus share export [-o FILE|-]            what you changed, your themes, scenes and layouts
    taurus share import FILE                   PREVIEW only: nothing is written
    taurus share import FILE --apply [...]     apply it (a settings backup is made first)

Export contains only what differs from the shipped defaults. It never contains personal or
machine-specific data (avatar, location, tokens, monitors, dock apps, paths), nor widget text or
images; the report says exactly what was left out.

A file you import is untrusted. It can only set options that exist in the shipped defaults with the
same type, themes are validated colour by colour, scenes go through the closed scene schema (no
commands exist in it), and every name is checked so nothing can be written outside Taurus' folders.
Layouts replace what you have, so they are opt-in (--layouts) and the old file is kept.
Matugen app overrides are never exported or imported: they write into other apps' config files.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TAURUS_DIR = os.environ.get("TAURUS_DIR") or os.path.dirname(HERE)
FORMAT = "taurus-setup"
VERSION = 1
MAX_FILE = 1024 * 1024
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _-]{0,40}$")
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
MONITOR_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,39}$")
THEME_KEYS = ["base", "mantle", "crust", "text", "subtext0", "subtext1", "surface0", "surface1", "surface2",
              "overlay0", "overlay1", "overlay2", "blue", "sapphire", "peach", "green", "red", "mauve", "pink",
              "yellow", "maroon", "teal"]
# Settings that describe this machine or its owner, or are runtime state: never exported, never imported.
DENY_PATHS = [("display", "monitors"), ("dock", "apps"), ("notifications", "soundFile"),
              ("general", "avatarPath"), ("theme", "colors"), ("scenes", "auto"), ("notifications", "dnd"),
              ("idle", "manualInhibit"), ("idle", "caffeineStartTime"), ("idle", "caffeineEndTime"), ("syspanel",)]
# matched per key segment: "city" must not catch "opacity", nor "auth" catch "autohide"
DENY_KEY = re.compile(r"token|secret|passw|api[_-]?key|cookie|e-?mail|location|latitude|longitude|avatar|"
                      r"webhook|username|account|^(auth|city|coords?|lat|lon|lng)$", re.I)
LAYOUT_KEEP = ["type", "wType", "wVariant", "wX", "wY", "wWidth", "wHeight", "wOpacity", "wRotation",
               "stretchWidth", "stretchHeight"]


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


scene_mod = load_module("scene")


# ---- paths ----------------------------------------------------------------------------------------

def settings_path():
    return scene_mod.settings_path()


def state_dir():
    return scene_mod.state_dir()


def themes_dir():
    return os.path.join(state_dir(), "themes")


def widgets_dir():
    return os.path.join(state_dir(), "widgets")


def defaults_path():
    sibling = os.path.join(os.path.dirname(TAURUS_DIR), "config", "taurus", "settings.json")
    return sibling if os.path.isfile(sibling) else os.path.join(TAURUS_DIR, "assets", "settings.default.json")


def bundled_theme_names():
    d = os.path.join(TAURUS_DIR, "assets", "themes")
    return {f[:-5].lower() for f in os.listdir(d) if f.endswith(".json")} if os.path.isdir(d) else set()


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".share-")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


# ---- settings: flatten, filter -----------------------------------------------------------------------

def flatten(obj, prefix=()):
    """Leaves of a settings object as {path tuple: value}. Lists are leaves; empty objects are skipped."""
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.update(flatten(v, prefix + (k,)))
    else:
        out[prefix] = obj
    return out


def denied(path):
    if any(path[:len(d)] == d for d in DENY_PATHS):
        return "machine-specific or runtime state"
    if any(DENY_KEY.search(str(p)) for p in path):
        return "looks personal or secret"
    return None


def personal_value(value):
    """A string that holds a path or a home directory is personal even under an innocent key."""
    if isinstance(value, str):
        return value.startswith(("/", "~/")) or "/home/" in value
    if isinstance(value, list):
        return any(personal_value(v) for v in value)
    return False


def type_name(v):
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "list"
    return "object"


def safe_value(v, depth=0):
    """Limit what a file may put into a setting: small, shallow, plain data."""
    if depth > 4:
        return False
    if isinstance(v, str):
        return len(v) <= 200 and not any(ord(c) < 32 for c in v)
    if isinstance(v, (bool, int, float)) or v is None:
        return True
    if isinstance(v, list):
        return len(v) <= 100 and all(safe_value(i, depth + 1) for i in v)
    if isinstance(v, dict):
        return len(v) <= 50 and all(isinstance(k, str) and len(k) <= 64 and safe_value(i, depth + 1) for k, i in v.items())
    return False


def set_path(data, path, value):
    node = data
    for k in path[:-1]:
        if not isinstance(node.get(k), dict):
            node[k] = {}
        node = node[k]
    node[path[-1]] = value


# ---- export -----------------------------------------------------------------------------------------------

def export_settings(excluded):
    cur = flatten(read_json(settings_path(), {}) or {})
    base = flatten(read_json(defaults_path(), {}) or {})
    out = {}
    for path, value in sorted(cur.items()):
        if path in base and base[path] == value:
            continue
        why = denied(path) or ("holds a path" if personal_value(value) else None)
        if why:
            excluded.append({"what": "settings." + ".".join(map(str, path)), "why": why})
            continue
        set_path(out, path, value)
    return out


def export_themes(excluded):
    out = {}
    if os.path.isdir(themes_dir()):
        for fn in sorted(os.listdir(themes_dir())):
            if fn.endswith(".json"):
                clean, err = validate_theme(read_json(os.path.join(themes_dir(), fn)), fn[:-5])
                if clean:
                    out[clean["name"]] = clean
                else:
                    excluded.append({"what": "theme " + fn, "why": err})
    return out


def export_scenes(excluded):
    out = {}
    d = scene_mod.user_dir()
    if os.path.isdir(d):
        for fn in sorted(os.listdir(d)):
            if fn.endswith(".json"):
                clean, errs = scene_mod.validate_scene(read_json(os.path.join(d, fn)), fn[:-5])
                if clean:
                    out[clean["name"]] = clean
                else:
                    excluded.append({"what": "scene " + fn, "why": "; ".join(errs)})
    return out


def sanitize_layout(items):
    kept, stripped = [], 0
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        row = {}
        for k, v in item.items():
            if k in LAYOUT_KEEP:
                row[k] = v
            elif isinstance(v, (bool, int, float)) and k not in ("wImagePath", "imagePath") and k.isidentifier():
                row[k] = v            # numbers and flags cannot carry personal text
            else:
                stripped += 1
        kept.append(row)
    return kept, stripped


def export_layouts(excluded):
    out = {}
    if os.path.isdir(widgets_dir()):
        for mon in sorted(os.listdir(widgets_dir())):
            items = read_json(os.path.join(widgets_dir(), mon, "layout.json"))
            if items is None or not MONITOR_RE.match(mon):
                continue
            kept, stripped = sanitize_layout(items)
            out[mon] = kept
            if stripped:
                excluded.append({"what": f"layout {mon}", "why": f"{stripped} text, image or list value(s) removed from widgets"})
    return out


def cmd_export(args):
    out = "taurus-setup.json"
    if "-o" in args:
        i = args.index("-o")
        out = args[i + 1] if i + 1 < len(args) else out
    excluded = []
    bundle = {"format": FORMAT, "version": VERSION, "created": time.strftime("%Y-%m-%d"),
              "taurus_version": open(os.path.join(TAURUS_DIR, "version.txt")).read().strip()
              if os.path.exists(os.path.join(TAURUS_DIR, "version.txt")) else "unknown",
              "settings": export_settings(excluded), "themes": export_themes(excluded),
              "scenes": export_scenes(excluded), "layouts": export_layouts(excluded), "excluded": excluded}
    text = json.dumps(bundle, indent=2) + "\n"
    if out == "-":
        sys.stdout.write(text)
    else:
        with open(out, "w") as f:
            f.write(text)
        print(f"wrote {out}", file=sys.stderr)
    n = len(flatten(bundle["settings"]))
    print(f"exported: {n} setting(s), {len(bundle['themes'])} theme(s), {len(bundle['scenes'])} scene(s), "
          f"{len(bundle['layouts'])} layout(s); left out {len(excluded)} personal or machine-specific item(s)", file=sys.stderr)
    for e in excluded:
        print(f"  left out: {e['what']} ({e['why']})", file=sys.stderr)
    return 0


# ---- validation of incoming data -----------------------------------------------------------------------------

def validate_theme(obj, hint=None):
    if not isinstance(obj, dict):
        return None, "not an object"
    name = obj.get("name", hint)
    if not isinstance(name, str) or not NAME_RE.match(name):
        return None, "bad name"
    colors = obj.get("colors")
    if not isinstance(colors, dict):
        return None, "no colors"
    missing = [k for k in THEME_KEYS if k not in colors]
    bad = [k for k in THEME_KEYS if k in colors and not (isinstance(colors[k], str) and HEX_RE.match(colors[k]))]
    if missing or bad:
        return None, "colors must be all " + str(len(THEME_KEYS)) + " roles as #rrggbb"
    return {"name": name, "isColorFocused": bool(obj.get("isColorFocused", True)),
            "colors": {k: colors[k].lower() for k in THEME_KEYS}}, None


def load_bundle(path):
    try:
        if os.path.getsize(path) > MAX_FILE:
            return None, "file is larger than 1 MB"
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        return None, f"cannot read it as JSON: {e}"
    if not isinstance(data, dict) or data.get("format") != FORMAT:
        return None, "this is not a Taurus setup file"
    if data.get("version") != VERSION:
        return None, f"unsupported version {data.get('version')!r} (this Taurus reads version {VERSION})"
    return data, None


# Not written as raw settings: switching theme also writes the palette and regenerates the colours,
# so it goes through `taurus set theme ...` after the imported themes are in place.
THEME_SWITCH = [("theme", "activePreset"), ("theme", "matugen")]


def plan_settings(incoming, dropped):
    """Leaves of the incoming settings that this install accepts."""
    base = flatten(read_json(defaults_path(), {}) or {})
    cur = flatten(read_json(settings_path(), {}) or {})
    accepted = {}
    for path, value in flatten(incoming if isinstance(incoming, dict) else {}).items():
        name = "settings." + ".".join(map(str, path))
        if not path or not all(isinstance(k, str) for k in path):
            continue
        why = denied(path)
        if path in THEME_SWITCH:
            continue
        if why:
            dropped.append((name, why))
        elif path not in base:
            dropped.append((name, "not an option of this Taurus"))
        elif type_name(value) != type_name(base[path]):
            dropped.append((name, f"expected {type_name(base[path])}"))
        elif not safe_value(value):
            dropped.append((name, "value is too large or not plain data"))
        elif personal_value(value):
            dropped.append((name, "holds a path"))
        else:
            accepted[path] = (cur.get(path, base[path]), value)
    return accepted


def plan_named(kind, incoming, existing, bundled, validator, dropped, overwrite):
    """themes / scenes: -> list of (final name, clean object, action)."""
    plan = []
    for key, obj in (incoming.items() if isinstance(incoming, dict) else []):
        clean, err = validator(obj, key)
        if not clean:
            dropped.append((f"{kind} {key!r}", err if isinstance(err, str) else "; ".join(err)))
            continue
        name = clean["name"]
        orig = name
        action = "new"
        if name.lower() in bundled:
            name = name + "-shared"          # never shadow a bundled one silently
            if not NAME_RE.match(name):
                dropped.append((f"{kind} {key!r}", "name collides with a bundled one"))
                continue
            clean = dict(clean, name=name)
            action = "renamed (a bundled one has that name)"
        if name.lower() in existing:
            if not overwrite:
                plan.append((name, clean, "skipped (you already have it; use --overwrite)", orig))
                continue
            action = "overwrite"
        plan.append((name, clean, action, orig))
    return plan


def plan_layouts(incoming, dropped):
    plan = []
    for mon, items in (incoming.items() if isinstance(incoming, dict) else []):
        if not MONITOR_RE.match(mon):
            dropped.append((f"layout {mon!r}", "bad monitor name"))
        elif not os.path.isdir(os.path.join(widgets_dir(), mon)):
            dropped.append((f"layout {mon!r}", "no monitor with that name here"))
        elif not isinstance(items, list) or len(items) > 100:
            dropped.append((f"layout {mon!r}", "too many widgets or not a list"))
        else:
            kept, _ = sanitize_layout(items)
            plan.append((mon, kept))
    return plan


def plan_theme_switch(incoming, themes, dropped):
    """-> ("preset", name) | ("matugen", "on") | None"""
    inc = incoming.get("theme") if isinstance(incoming, dict) else None
    if not isinstance(inc, dict):
        return None
    if inc.get("matugen") is True:
        return ("matugen", "on")
    name = inc.get("activePreset")
    if not isinstance(name, str):
        return None
    renamed = {orig.lower(): final for final, _, _, orig in themes}
    final = renamed.get(name.lower())
    if final:
        return ("preset", final)
    if name.lower() in bundled_theme_names() or name.lower() in existing_names(themes_dir()):
        return ("preset", name)
    dropped.append((f"theme preset {name!r}", "not available here and not in the file"))
    return None


def existing_names(directory):
    try:
        return {f[:-5].lower() for f in os.listdir(directory) if f.endswith(".json")}
    except OSError:
        return set()


# ---- import ---------------------------------------------------------------------------------------------------

def taurus_bin():
    return os.path.join(os.path.dirname(TAURUS_DIR), "bin", "taurus")


def run_taurus(*args):
    """Run a taurus command. The settings were backed up once already, so skip the per-write backup."""
    env = dict(os.environ, TAURUS_NO_BACKUP="1")
    return subprocess.run([taurus_bin(), *args], env=env, capture_output=True, text=True, timeout=60).returncode == 0


def backup_settings():
    r = subprocess.run([taurus_bin(), "config", "backup"], capture_output=True, text=True, timeout=30)
    return r.returncode == 0


def cmd_import(args):
    files = [a for a in args if not a.startswith("--")]
    if not files:
        print("usage: taurus share import FILE [--apply] [--overwrite] [--layouts]", file=sys.stderr)
        return 1
    apply_, overwrite, with_layouts = "--apply" in args, "--overwrite" in args, "--layouts" in args
    data, err = load_bundle(files[0])
    if err:
        print(f"share: {err}", file=sys.stderr)
        return 1
    dropped = []
    settings = plan_settings(data.get("settings", {}), dropped)
    themes = plan_named("theme", data.get("themes", {}), existing_names(themes_dir()), bundled_theme_names(),
                        validate_theme, dropped, overwrite)
    scenes = plan_named("scene", data.get("scenes", {}), existing_names(scene_mod.user_dir()),
                        existing_names(scene_mod.bundled_dir()), scene_mod.validate_scene, dropped, overwrite)
    layouts = plan_layouts(data.get("layouts", {}), dropped) if with_layouts else []
    switch = plan_theme_switch(data.get("settings", {}), themes, dropped)

    changed = {p: v for p, v in settings.items() if v[0] != v[1]}
    print(f"From: Taurus {data.get('taurus_version', '?')}, {data.get('created', '?')}")
    print(f"\nSettings: {len(changed)} to change")
    for p, (old, new) in sorted(changed.items()):
        print(f"  {'.'.join(p)}: {json.dumps(old)} -> {json.dumps(new)}")
    for label, plan in (("Themes", themes), ("Scenes", scenes)):
        print(f"\n{label}: {len(plan)}")
        for name, _, action, _ in plan:
            print(f"  {name}: {action}")
    if switch:
        print("\nTheme: switch to " + (switch[1] if switch[0] == "preset" else "follow the wallpaper (Matugen)"))
    if with_layouts:
        print(f"\nLayouts: {len(layouts)}")
        for mon, items in layouts:
            print(f"  {mon}: {len(items)} widget(s); your current layout is kept as layout.json.bak")
    elif data.get("layouts"):
        print(f"\nLayouts: {len(data['layouts'])} in the file, not imported (add --layouts to replace yours)")
    if dropped:
        print(f"\nIgnored ({len(dropped)}):")
        for what, why in dropped[:20]:
            print(f"  {what}: {why}")
        if len(dropped) > 20:
            print(f"  ... and {len(dropped) - 20} more")

    if not apply_:
        print("\nThis was a preview: nothing was changed. Apply it with: taurus share import FILE --apply")
        return 0

    if changed and not backup_settings():
        print("share: could not back up your settings first; nothing was changed", file=sys.stderr)
        return 1
    if changed:
        cur = read_json(settings_path(), {}) or {}
        for p, (_, new) in changed.items():
            set_path(cur, p, new)
        write_json(settings_path(), cur)
    for name, clean, action, _ in themes:
        if action.startswith("skipped"):
            continue
        write_json(os.path.join(themes_dir(), name + ".json"), dict(clean, isCustom=True, category="user"))
    for name, clean, action, _ in scenes:
        if action.startswith("skipped"):
            continue
        write_json(os.path.join(scene_mod.user_dir(), name + ".json"), clean)
    if switch:
        args = ("set", "theme", "preset", switch[1]) if switch[0] == "preset" else ("set", "theme", "matugen", "on")
        if not run_taurus(*args):
            print(f"share: could not switch the theme ({' '.join(args)}); the themes were imported", file=sys.stderr)
    for mon, items in layouts:
        target = os.path.join(widgets_dir(), mon, "layout.json")
        if os.path.exists(target):
            os.replace(target, target + ".bak")
        write_json(target, items)
    applied = (len(changed) + sum(1 for _, _, a, _ in themes + scenes if not a.startswith("skipped"))
               + len(layouts) + (1 if switch else 0))
    print(f"\nApplied {applied} change(s). Undo the settings with: taurus config restore latest")
    return 0


def main(argv):
    if not argv:
        print("usage: taurus share <export [-o FILE|-]|import FILE [--apply] [--overwrite] [--layouts]>", file=sys.stderr)
        return 1
    if argv[0] == "export":
        return cmd_export(argv[1:])
    if argv[0] in ("import", "inspect"):
        return cmd_import(argv[1:])
    print("usage: taurus share <export [-o FILE|-]|import FILE [--apply] [--overwrite] [--layouts]>", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
