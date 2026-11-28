#!/usr/bin/env python3
"""Resolution, refresh rate, variable refresh rate (VRR) and rotation of the outputs, for niri.

  display-output.py info                          JSON list of the outputs with their modes
  display-output.py apply <output> [--mode WxH@Hz] [--vrr off|always|games] [--transform T]
                                                  change the output now (temporary, like `niri msg output`)
  display-output.py persist <output>              write the output's current mode, scale, rotation and VRR
                                                  into niri's output.kdl, between Taurus markers

`apply` is temporary on purpose: the settings page applies a change, asks the user to confirm it and only
then calls `persist`, so a mode the screen cannot show never ends up in the config.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

TRANSFORMS = {  # niri IPC name -> niri msg / KDL name
    "Normal": "normal", "_90": "90", "_180": "180", "_270": "270",
    "Flipped": "flipped", "Flipped90": "flipped-90", "Flipped180": "flipped-180", "Flipped270": "flipped-270",
}
VALID_TRANSFORMS = set(TRANSFORMS.values())
NAME_RE = re.compile(r"^[A-Za-z0-9_.:+-]+$")


def fail(msg, code=1):
    print("display-output: " + msg, file=sys.stderr)
    sys.exit(code)


def niri(*args, json_out=False):
    cmd = ["niri", "msg"] + (["--json"] if json_out else []) + list(args)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as e:
        fail("could not run niri: %s" % e)
    if res.returncode != 0:
        fail((res.stderr or res.stdout).strip() or "niri failed")
    return json.loads(res.stdout) if json_out else res.stdout


def state_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "taurus", "display-vrr.json")


def read_state():
    try:
        with open(state_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def write_state(name, mode):
    state = read_state()
    state[name] = mode
    os.makedirs(os.path.dirname(state_path()), exist_ok=True)
    with open(state_path(), "w", encoding="utf-8") as f:
        json.dump(state, f)


def saved_vrr_mode(name):
    """VRR mode written by Taurus in output.kdl for this output, or None."""
    path = output_kdl_path()
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(re.escape("// >>> taurus output %s >>>" % name) + r"(.*?)" + re.escape("// <<< taurus output %s <<<" % name), text, re.S)
    if not m:
        return None
    line = re.search(r"^\s*variable-refresh-rate(.*)$", m.group(1), re.M)
    if not line:
        return "off"
    return "games" if re.search(r"on-demand\s*=\s*true", line.group(1)) else "always"


def vrr_mode(name, enabled):
    """Current VRR mode. niri only says whether VRR is on right now, so the chosen mode is remembered."""
    mode = read_state().get(name) or saved_vrr_mode(name)
    if mode in ("off", "always", "games"):
        return mode
    return "always" if enabled else "off"


def read_outputs():
    raw = niri("outputs", json_out=True)
    outs = []
    for name in sorted(raw):
        o = raw[name]
        modes = o.get("modes", [])
        cur_idx = o.get("current_mode")
        cur = modes[cur_idx] if isinstance(cur_idx, int) and 0 <= cur_idx < len(modes) else None
        logical = o.get("logical") or {}
        by_res = {}
        for m in modes:
            by_res.setdefault((m["width"], m["height"]), set()).add(m["refresh_rate"])
        resolutions = [{"width": w, "height": h, "rates": sorted(r, reverse=True)}
                       for (w, h), r in sorted(by_res.items(), key=lambda kv: (-kv[0][0] * kv[0][1], -kv[0][0]))]
        outs.append({
            "name": name,
            "make": o.get("make", ""), "model": o.get("model", ""),
            "enabled": logical != {},
            "vrr_supported": bool(o.get("vrr_supported")),
            "vrr_enabled": bool(o.get("vrr_enabled")),
            "vrr_mode": vrr_mode(name, bool(o.get("vrr_enabled"))),
            "transform": TRANSFORMS.get(logical.get("transform", "Normal"), "normal"),
            "scale": logical.get("scale", 1.0),
            "custom_mode": bool(o.get("is_custom_mode")),
            "current": {"width": cur["width"], "height": cur["height"], "refresh": cur["refresh_rate"]} if cur else None,
            "resolutions": resolutions,
        })
    return outs


def get_output(name):
    for o in read_outputs():
        if o["name"] == name:
            return o
    fail("unknown output: %s" % name)


def mode_string(width, height, refresh_mhz):
    return "%dx%d@%.3f" % (width, height, refresh_mhz / 1000.0)


def cmd_apply(args):
    out = get_output(args.output)
    if args.mode:
        if not re.fullmatch(r"\d+x\d+(@\d+(\.\d+)?)?", args.mode):
            fail("bad mode: %s" % args.mode)
        niri("output", args.output, "mode", args.mode)
    if args.transform:
        if args.transform not in VALID_TRANSFORMS:
            fail("bad transform: %s" % args.transform)
        niri("output", args.output, "transform", args.transform)
    if args.vrr:
        if args.vrr not in ("off", "always", "games"):
            fail("bad vrr value: %s" % args.vrr)
        if args.vrr != "off" and not out["vrr_supported"]:
            fail("%s does not support variable refresh rate" % args.output)
        if args.vrr == "games":
            ensure_game_rule()
            niri("output", args.output, "vrr", "on", "--on-demand")
        else:
            niri("output", args.output, "vrr", "on" if args.vrr == "always" else "off")
        write_state(args.output, args.vrr)


def output_kdl_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.environ.get("TAURUS_NIRI_OUTPUT_FILE") or os.path.join(base, "niri", "config", "output.kdl")


GAME_RULE_START = "// >>> taurus vrr games >>>"
GAME_RULE_END = "// <<< taurus vrr games <<<"
GAME_RULE = GAME_RULE_START + r'''
// Windows that turn VRR on when an output is set to "only in games". Add your own `match` lines.
window-rule {
    match app-id=r#"^steam_app_\d+$"#
    match app-id="gamescope"
    variable-refresh-rate true
}
''' + GAME_RULE_END + "\n"


def write_config(path, new):
    """Write output.kdl atomically and make sure niri still accepts the config, else undo."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    had_file = os.path.exists(path)
    if had_file:
        shutil.copy2(path, path + ".taurus-bak")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".output.kdl.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new)
    os.replace(tmp, path)
    # niri keeps running with the old config when a new one is invalid, but do not leave a broken file behind
    main_cfg = os.path.join(os.path.dirname(os.path.dirname(path)), "config.kdl")
    if shutil.which("niri") and os.path.exists(main_cfg) and not os.environ.get("TAURUS_SKIP_VALIDATE"):
        res = subprocess.run(["niri", "validate", "-c", main_cfg], capture_output=True, text=True)
        if res.returncode != 0:
            if had_file:
                shutil.copy2(path + ".taurus-bak", path)
            else:
                os.remove(path)
            fail("niri rejected the config, nothing was changed: " + (res.stderr or res.stdout).strip()[-300:], 4)


def ensure_game_rule():
    """Add the window rule for games once; an existing block (maybe edited by the user) is left alone."""
    path = output_kdl_path()
    old = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    if GAME_RULE_START in old:
        return
    write_config(path, old + ("" if old.endswith("\n") or not old else "\n") + GAME_RULE)


def render_block(o):
    lines = ['output "%s" {' % o["name"]]
    if o["current"] and not o["custom_mode"]:
        c = o["current"]
        lines.append('    mode "%s"' % mode_string(c["width"], c["height"], c["refresh"]))
    lines.append("    scale %s" % ("%g" % o["scale"]))
    lines.append('    transform "%s"' % o["transform"])
    if o["vrr_mode"] == "always":
        lines.append("    variable-refresh-rate")
    elif o["vrr_mode"] == "games":
        lines.append("    variable-refresh-rate on-demand=true")
    lines.append("}")
    start = "// >>> taurus output %s >>>" % o["name"]
    end = "// <<< taurus output %s <<<" % o["name"]
    return "\n".join([start] + lines + [end]) + "\n"


def cmd_persist(args):
    if not NAME_RE.match(args.output):
        fail("bad output name: %s" % args.output)
    o = get_output(args.output)
    path = output_kdl_path()
    old = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    start = "// >>> taurus output %s >>>" % args.output
    end = "// <<< taurus output %s <<<" % args.output
    block = render_block(o)
    pat = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
    if pat.search(old):
        new = pat.sub(lambda _m: block, old)
    else:
        # an output block of the user's own for the same screen wins: never write a second one
        if re.search(r'^\s*output\s+"%s"\s*\{' % re.escape(args.output), old, re.M):
            fail('%s already has its own output "%s" block; edit that one by hand' % (path, args.output), 3)
        new = old + ("" if old.endswith("\n") or not old else "\n") + block
    write_config(path, new)
    print("saved %s" % path)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info")
    a = sub.add_parser("apply")
    a.add_argument("output")
    a.add_argument("--mode")
    a.add_argument("--vrr")
    a.add_argument("--transform")
    s = sub.add_parser("persist")
    s.add_argument("output")
    args = p.parse_args()
    if args.cmd == "info":
        print(json.dumps(read_outputs()))
    elif args.cmd == "apply":
        cmd_apply(args)
    else:
        cmd_persist(args)


if __name__ == "__main__":
    main()
