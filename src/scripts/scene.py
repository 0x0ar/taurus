#!/usr/bin/env python3
"""Taurus scenes: named bundles of settings that switch together, by hand or automatically.

A scene is a JSON file with a FIXED set of typed fields. There are no command strings, so a scene
that someone shares can never run anything, and every field can be read back and restored.

    {
      "name": "gaming",
      "description": "No interruptions while a game is focused",
      "dnd": true, "dock_autohide": true, "bar_autohide": true, "mute_sfx": true,
      "caffeine": true, "theme": "Taurus", "gamma_temperature": 6500,
      "triggers": {"apps": ["steam", "gamescope"], "time": {"from": "22:00", "to": "07:00"}}
    }

Applying a scene remembers the previous value of every field it touches (the base). Turning the
scene off puts a field back only if it still holds what the scene wrote: a value the user changed
meanwhile is kept. Scene writes bypass the settings backup rotation on purpose: switching scenes
automatically must not push the user's own backups out, and the base in scene.json is the undo.

usage: scene.py <list|show|apply|off|status|save|delete|auto|tick|validate> ...
"""
import fnmatch
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TAURUS_DIR = os.environ.get("TAURUS_DIR") or os.path.dirname(HERE)
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _-]{0,40}$")
TIME_RE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
# "Nothing focused" matches no app trigger. The shell's own windows (the launcher, panels) and
# unknown classes are IGNORED: opening the launcher must not end a game scene.
NO_APP = {"", "desktop"}
IGNORED = {"unknown", "quickshell"}
MAX_FILE = 64 * 1024

# field -> (settings path, type). theme and gamma_temperature are handled separately.
SETTING_FIELDS = {
    "dnd": (("notifications", "dnd"), bool),
    "dock_autohide": (("dock", "autohide"), bool),
    "bar_autohide": (("bar", "autohide"), bool),
    "mute_sfx": (("general", "muteSfx"), bool),
    "caffeine": (("idle", "manualInhibit"), bool),
}
FIELDS = list(SETTING_FIELDS) + ["theme", "gamma_temperature"]
META = {"name", "description", "triggers"}


# ---- paths -------------------------------------------------------------------------------------

def settings_path():
    return os.environ.get("QS_SETTINGS") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "taurus", "settings.json")


def state_dir():
    return os.environ.get("QS_STATE_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "taurus")


def user_dir():
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "taurus", "scenes")


def bundled_dir():
    return os.path.join(TAURUS_DIR, "assets", "scenes")


def state_file():
    return os.path.join(state_dir(), "scene.json")


# ---- settings (atomic, no backup) ---------------------------------------------------------------

def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".scene-")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def get_path(obj, path, default=None):
    for key in path:
        if not isinstance(obj, dict) or key not in obj:
            return default
        obj = obj[key]
    return obj


def set_settings(changes):
    """changes: {(path tuple): value}. One atomic write for all of them."""
    data = read_json(settings_path(), {})
    if not isinstance(data, dict):
        data = {}
    for path, value in changes.items():
        node = data
        for key in path[:-1]:
            if not isinstance(node.get(key), dict):
                node[key] = {}
            node = node[key]
        node[path[-1]] = value
    write_json(settings_path(), data)


# ---- field getters / setters --------------------------------------------------------------------

def taurus_bin():
    return os.path.join(os.path.dirname(TAURUS_DIR), "bin", "taurus")


def run_taurus(*args):
    env = dict(os.environ, TAURUS_NO_BACKUP="1")
    return subprocess.run([taurus_bin(), *args], env=env, capture_output=True, text=True, timeout=60)


def gamma_script():
    return os.path.join(TAURUS_DIR, "scripts", "gamma.sh")


def gamma_available():
    return subprocess.run(["sh", "-c", "command -v taurus-gamma"], capture_output=True).returncode == 0


def gamma_run(*args):
    return subprocess.run(["taurus-gamma", *args], capture_output=True, text=True, timeout=20).returncode == 0


def gamma_status():
    """The running filter's state, or None when the daemon is not running or taurus-gamma is missing.
    `taurus-gamma status` prints `temperature N`, `auto true|false`, `day-temperature N`, `night-temperature N`."""
    try:
        r = subprocess.run(["taurus-gamma", "status"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None

    def num(key):
        m = re.search(rf"^{key}\s+(\d+)", r.stdout, re.M)
        return int(m.group(1)) if m else None

    temp = num("temperature")
    if temp is None:
        return None
    return {"auto": bool(re.search(r"^auto\s+true\b", r.stdout, re.M)), "temperature": temp,
            "day": num("day-temperature") or 6500, "night": num("night-temperature") or 4000}


def get_field(field):
    settings = read_json(settings_path(), {})
    if field in SETTING_FIELDS:
        path, typ = SETTING_FIELDS[field]
        return bool(get_path(settings, path, False))
    if field == "theme":
        theme = settings.get("theme") if isinstance(settings.get("theme"), dict) else {}
        if theme.get("matugen") is True:
            return "matugen"
        return theme.get("activePreset") or "Taurus"
    if field == "gamma_temperature":
        # A daemon that is not running starts neutral when the scene sets a temperature.
        return gamma_status() or {"auto": False, "temperature": 6500, "day": 6500, "night": 4000}
    return None


def set_field(field, value, restoring=False):
    """Apply one field. Returns True on success."""
    if field in SETTING_FIELDS:
        path, _ = SETTING_FIELDS[field]
        changes = {path: bool(value)}
        if field == "caffeine" and not value:
            changes[("idle", "caffeineStartTime")] = 0
            changes[("idle", "caffeineEndTime")] = 0
        set_settings(changes)
        return True
    if field == "theme":
        if value == "matugen" or (restoring and value == "Matugen"):
            result = run_taurus("set", "theme", "matugen", "on")
        else:
            result = run_taurus("set", "theme", "preset", str(value))
        return result.returncode == 0
    if field == "gamma_temperature":
        if not gamma_available():
            return False
        if restoring:
            if not isinstance(value, dict):
                return False
            if value.get("auto"):
                # setting a temperature switched the day/night schedule off: switch it back on
                return gamma_run("auto", "on", "--day", str(value["day"]), "--night", str(value["night"]))
            return subprocess.run(["bash", gamma_script(), "set", str(int(value["temperature"]))],
                                  capture_output=True, timeout=20).returncode == 0
        return subprocess.run(["bash", gamma_script(), "set", str(int(value))],
                              capture_output=True, timeout=20).returncode == 0
    return False


# ---- scene files ----------------------------------------------------------------------------------

def validate_scene(obj, name_hint=None):
    """Return (clean_scene, errors). Unknown keys are errors: a scene is a closed schema."""
    errors = []
    if not isinstance(obj, dict):
        return None, ["a scene must be a JSON object"]
    clean = {}
    name = obj.get("name", name_hint)
    if not isinstance(name, str) or not NAME_RE.match(name):
        errors.append("name must be 1-41 characters: letters, digits, space, _ or -")
    else:
        clean["name"] = name
    for key in obj:
        if key not in FIELDS and key not in META:
            errors.append(f"unknown field '{key}'")
    desc = obj.get("description", "")
    if not isinstance(desc, str) or len(desc) > 200:
        errors.append("description must be text up to 200 characters")
    else:
        clean["description"] = desc
    for field in SETTING_FIELDS:
        if field in obj:
            if not isinstance(obj[field], bool):
                errors.append(f"{field} must be true or false")
            else:
                clean[field] = obj[field]
    if "theme" in obj:
        t = obj["theme"]
        if not isinstance(t, str) or not (t == "matugen" or NAME_RE.match(t)):
            errors.append("theme must be a preset name or 'matugen'")
        else:
            clean["theme"] = t
    if "gamma_temperature" in obj:
        g = obj["gamma_temperature"]
        if isinstance(g, bool) or not isinstance(g, int) or not 1000 <= g <= 10000:
            errors.append("gamma_temperature must be a whole number from 1000 to 10000")
        else:
            clean["gamma_temperature"] = g
    trig = obj.get("triggers", {})
    ctrig = {}
    if not isinstance(trig, dict):
        errors.append("triggers must be an object")
    else:
        for key in trig:
            if key not in ("apps", "time"):
                errors.append(f"unknown trigger '{key}'")
        apps = trig.get("apps")
        if apps is not None:
            if (not isinstance(apps, list) or len(apps) > 20
                    or not all(isinstance(a, str) and re.match(r"^[\w.*+-]{1,64}$", a) for a in apps)):
                errors.append("triggers.apps must be up to 20 window classes (letters, digits, . _ - * +)")
            else:
                ctrig["apps"] = apps
        tm = trig.get("time")
        if tm is not None:
            if (not isinstance(tm, dict) or set(tm) != {"from", "to"}
                    or not all(isinstance(v, str) and TIME_RE.match(v) for v in tm.values())):
                errors.append("triggers.time must be {\"from\": \"HH:MM\", \"to\": \"HH:MM\"}")
            else:
                ctrig["time"] = tm
    if ctrig:
        clean["triggers"] = ctrig
    if not any(f in clean for f in FIELDS):
        errors.append("a scene must set at least one field")
    return (clean if not errors else None), errors


def scene_files():
    """name(lowercase) -> (path, source). The user's scenes win over bundled ones."""
    found = {}
    for source, d in (("bundled", bundled_dir()), ("user", user_dir())):
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for fn in names:
            if fn.endswith(".json"):
                found[fn[:-5].lower()] = (os.path.join(d, fn), source)
    return found


def load_scene(name):
    entry = scene_files().get(str(name).lower())
    if not entry:
        return None, None, [f"no scene named '{name}'"]
    path, source = entry
    try:
        if os.path.getsize(path) > MAX_FILE:
            return None, source, ["scene file is too large"]
        raw = json.load(open(path))
    except (OSError, ValueError) as e:
        return None, source, [f"cannot read {path}: {e}"]
    clean, errors = validate_scene(raw, os.path.basename(path)[:-5])
    return clean, source, errors


# ---- state ------------------------------------------------------------------------------------------

def load_state():
    s = read_json(state_file(), {})
    return s if isinstance(s, dict) and s.get("active") else {}


def still_ours(field, current, written):
    """Does the field still hold what the scene wrote? (gamma: a manual temperature, schedule off)"""
    if field == "gamma_temperature":
        return bool(current) and not current["auto"] and current["temperature"] == written
    return current == written


def restore(state):
    """Put back every field that still holds what the scene wrote. Returns (restored, kept)."""
    restored, kept = [], []
    for field, before in (state.get("base") or {}).items():
        written = (state.get("applied") or {}).get(field)
        if still_ours(field, get_field(field), written):
            (restored if set_field(field, before, restoring=True) else kept).append(field)
        else:
            kept.append(field)
    try:
        os.remove(state_file())
    except OSError:
        pass
    return restored, kept


def cmd_apply(name, source="manual"):
    scene, _, errors = load_scene(name)
    if errors:
        print("scene: " + "; ".join(errors), file=sys.stderr)
        return 1
    state = load_state()
    if state:
        restore(state)
    base, applied, failed = {}, {}, []
    for field in FIELDS:
        if field not in scene:
            continue
        before = get_field(field)
        if set_field(field, scene[field]):
            base[field] = before
            applied[field] = scene[field]
        else:
            failed.append(field)
    write_json(state_file(), {"active": scene["name"], "source": source, "base": base,
                              "applied": applied, "since": int(time.time())})
    print(f"scene '{scene['name']}' active ({len(applied)} settings)")
    for f in failed:
        print(f"scene: could not set {f}", file=sys.stderr)
    return 0


def cmd_off():
    state = load_state()
    if not state:
        print("no scene is active")
        return 0
    restored, kept = restore(state)
    print(f"scene '{state['active']}' off: restored {len(restored)}, kept {len(kept)} you changed")
    return 0


# ---- triggers -----------------------------------------------------------------------------------------

def time_in(window, minutes):
    h1, m1 = map(int, window["from"].split(":"))
    h2, m2 = map(int, window["to"].split(":"))
    a, b = h1 * 60 + m1, h2 * 60 + m2
    if a == b:
        return False
    return a <= minutes < b if a < b else (minutes >= a or minutes < b)  # crosses midnight


def match(app, minutes):
    """Name of the scene that should be active for this focused app and time, or None.
    Priority: a matching app, then a matching time; ties go to the first name alphabetically."""
    app = (app or "").strip().lower()
    by_app, by_time = [], []
    for key in sorted(scene_files()):
        scene, _, errors = load_scene(key)
        if errors or not scene:
            continue
        trig = scene.get("triggers", {})
        if app not in NO_APP and any(fnmatch.fnmatch(app, a.lower()) for a in trig.get("apps", [])):
            by_app.append(scene["name"])
        if "time" in trig and time_in(trig["time"], minutes):
            by_time.append(scene["name"])
    return (by_app or by_time or [None])[0]


def auto_enabled():
    return get_path(read_json(settings_path(), {}), ("scenes", "auto"), False) is True


def cmd_tick(app, now=None):
    if not auto_enabled():
        return 0
    state = load_state()
    if (app or "").strip().lower() in IGNORED:
        return 0
    if state and state.get("source") == "manual":
        return 0  # the user chose a scene by hand: automatic switching stays out of the way
    lt = time.localtime(now)
    want = match(app, lt.tm_hour * 60 + lt.tm_min)
    have = state.get("active") if state else None
    if want == have:
        return 0
    if want is None:
        return cmd_off()
    return cmd_apply(want, "auto")


# ---- commands ----------------------------------------------------------------------------------------------

def cmd_list(as_json):
    state = load_state()
    rows = []
    for key in sorted(scene_files()):
        scene, source, errors = load_scene(key)
        rows.append({"name": (scene or {}).get("name", key), "source": source, "valid": not errors,
                     "description": (scene or {}).get("description", ""),
                     "triggers": (scene or {}).get("triggers", {}),
                     "active": bool(state) and state.get("active", "").lower() == key, "errors": errors})
    if as_json:
        print(json.dumps(rows, indent=2))
    else:
        for r in rows:
            flag = "*" if r["active"] else " "
            bad = "" if r["valid"] else "  (invalid: " + "; ".join(r["errors"]) + ")"
            print(f"{flag} {r['name']:<14} {r['source']:<8} {r['description']}{bad}")
    return 0


def cmd_show(name):
    scene, source, errors = load_scene(name)
    if errors:
        print("scene: " + "; ".join(errors), file=sys.stderr)
        return 1
    print(json.dumps(dict(scene, source=source), indent=2))
    return 0


def cmd_status(as_json):
    state = load_state()
    out = {"active": state.get("active"), "source": state.get("source"), "since": state.get("since"),
           "auto": auto_enabled(), "applied": state.get("applied", {})}
    if as_json:
        print(json.dumps(out, indent=2))
    else:
        print(f"active: {out['active'] or 'none'}" + (f" ({out['source']})" if out["active"] else ""))
        print(f"auto: {'on' if out['auto'] else 'off'}")
    return 0


def cmd_save(name, fields):
    if not NAME_RE.match(name):
        print("scene: invalid name", file=sys.stderr)
        return 1
    names = fields or ["dnd", "dock_autohide", "bar_autohide", "mute_sfx", "theme"]
    bad = [f for f in names if f not in FIELDS]
    if bad:
        print("scene: unknown field(s): " + ", ".join(bad), file=sys.stderr)
        return 1
    scene = {"name": name, "description": "Saved from the current settings"}
    for f in names:
        value = get_field(f)
        if value is not None:
            scene[f] = value
    clean, errors = validate_scene(scene)
    if errors:
        print("scene: " + "; ".join(errors), file=sys.stderr)
        return 1
    write_json(os.path.join(user_dir(), name + ".json"), clean)
    print(f"saved {os.path.join(user_dir(), name + '.json')}")
    return 0


def cmd_delete(name):
    entry = scene_files().get(name.lower())
    if not entry or entry[1] != "user":
        print("scene: only your own scenes can be deleted", file=sys.stderr)
        return 1
    state = load_state()
    if state and state.get("active", "").lower() == name.lower():
        cmd_off()
    os.remove(entry[0])
    print(f"deleted {name}")
    return 0


def cmd_auto(action):
    if action in (None, "status"):
        print("on" if auto_enabled() else "off")
        return 0
    if action not in ("on", "off"):
        print("usage: taurus scene auto <on|off|status>", file=sys.stderr)
        return 1
    result = subprocess.run([taurus_bin(), "config", "set", "scenes.auto", "true" if action == "on" else "false"],
                            capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    return result.returncode


def usage():
    print("usage: taurus scene <list [--json]|show <name>|apply <name>|off|status [--json]|"
          "save <name> [fields...]|delete <name>|auto <on|off|status>>", file=sys.stderr)
    return 1


def main(argv):
    if not argv:
        return usage()
    cmd, rest = argv[0], argv[1:]
    if cmd == "list":
        return cmd_list("--json" in rest)
    if cmd == "show" and rest:
        return cmd_show(rest[0])
    if cmd == "apply" and rest:
        return cmd_apply(rest[0])
    if cmd == "off":
        return cmd_off()
    if cmd == "status":
        return cmd_status("--json" in rest)
    if cmd == "save" and rest:
        return cmd_save(rest[0], rest[1:])
    if cmd == "delete" and rest:
        return cmd_delete(rest[0])
    if cmd == "auto":
        return cmd_auto(rest[0] if rest else None)
    if cmd == "tick":
        return cmd_tick(rest[0] if rest else "")
    return usage()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
