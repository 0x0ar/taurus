#!/usr/bin/env python3
"""taurus doctor: find (and conservatively fix) the things that keep the Taurus shell from running.

    taurus doctor [--json]        read-only report; exit 0 all good, 1 warnings, 2 failures
    taurus doctor --fix           also apply the SAFE repairs listed below

Safe repairs, and nothing else:
  * settings.json does not parse   -> restore the last known good copy, or the newest backup that
                                      parses (the broken file is kept next to it)
  * stale daemon pid/lock files    -> remove them
  * an active scene whose file is gone -> undo it
A QML error is a code problem: settings are NEVER restored for it, that would throw away valid changes.

Used by taurusd (not meant to be typed): preflight, recovered, gave-up, mark-good, announce, terminal.
"""
import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TAURUS_DIR = os.environ.get("TAURUS_DIR") or os.path.dirname(HERE)
LOG_ERROR = re.compile(r"\bERROR\b|TypeError|ReferenceError|is not a type|unavailable", re.I)
# errors that say something about the machine, not about the shell
BENIGN = re.compile(r"pipewire|quickshell\.ipc|PolicyKit|polkit|portal|Failed to start IPC", re.I)


# ---- paths ------------------------------------------------------------------------------------

def settings_path():
    return os.environ.get("QS_SETTINGS") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "taurus", "settings.json")


def state_dir():
    return os.environ.get("QS_STATE_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "taurus")


def pid_file():
    return os.environ.get("TAURUS_PID_FILE", "/tmp/taurusd.pid")


def lock_file():
    return os.environ.get("TAURUS_LOCK_FILE", "/tmp/taurusd.lock")


def last_good():
    return os.path.join(state_dir(), "last-good", "settings.json")


def recovery_file():
    return os.path.join(state_dir(), "recovery.json")


# ---- helpers -----------------------------------------------------------------------------------

def parses(path):
    try:
        with open(path) as f:
            return isinstance(json.load(f), dict)
    except (OSError, ValueError):
        return False


def alive(pid):
    try:
        os.kill(int(pid), 0)
    except (OSError, ValueError):
        return False
    try:
        with open(f"/proc/{int(pid)}/stat") as f:
            return ") Z" not in f.read()
    except OSError:
        return True


def read_pid():
    try:
        return int(open(pid_file()).read().strip())
    except (OSError, ValueError):
        return None


def shell_pids():
    """Quickshell processes running THIS install's shell (never someone else's)."""
    pattern = f"quickshell.* -p {re.escape(TAURUS_DIR)}/quickshell"
    out = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True).stdout.split()
    return [int(p) for p in out if int(p) != os.getpid()]


def log_lines(pid, tail=400):
    """The log of one instance. A bare `quickshell log` looks for a 'default' config and finds nothing
    (or another shell's log), so the instance is always selected by pid."""
    try:
        r = subprocess.run(["quickshell", "log", "--pid", str(pid), "--tail", str(tail)],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.splitlines() if r.returncode == 0 else None


def real_errors(lines):
    clean = lambda l: re.sub(r"\x1b\[[0-9;]*m", "", l)
    return [clean(l) for l in lines if LOG_ERROR.search(clean(l)) and not BENIGN.search(clean(l))]


def backups():
    return sorted(glob.glob(os.path.join(state_dir(), "backups", "settings.*.json")),
                  key=os.path.getmtime, reverse=True)


def check(cid, status, message, fixable=False, detail=None):
    c = {"id": cid, "status": status, "message": message, "fixable": fixable}
    if detail:
        c["detail"] = detail
    return c


# ---- checks ---------------------------------------------------------------------------------------

def run_checks():
    checks = []
    sp = settings_path()
    if not os.path.exists(sp):
        checks.append(check("settings", "ok", "no settings.json yet (defaults are used)"))
    elif parses(sp):
        checks.append(check("settings", "ok", "settings.json is valid"))
    else:
        source = last_good() if parses(last_good()) else next((b for b in backups() if parses(b)), None)
        checks.append(check("settings", "fail", "settings.json is not valid JSON", True,
                            f"can restore from {source}" if source else "no valid backup to restore from"))

    pid = read_pid()
    daemon_up = pid is not None and alive(pid)
    stale = [f for f in (pid_file(), lock_file()) if os.path.exists(f)] if not daemon_up else []
    if stale:
        checks.append(check("daemon-files", "warn", "stale daemon pid/lock files from a daemon that is gone", True, ", ".join(stale)))
    else:
        checks.append(check("daemon-files", "ok", "daemon pid/lock files are consistent"))

    shells = shell_pids()
    if shells:
        checks.append(check("shell", "ok", f"the shell is running (pid {shells[0]})"))
    else:
        checks.append(check("shell", "fail" if daemon_up else "warn",
                            "the shell is not running" + (" although the daemon is" if daemon_up else "")))

    lines = log_lines(shells[0]) if shells else None
    if lines is None:
        checks.append(check("log", "ok", "no running shell log to read"))
    else:
        errs = real_errors(lines)
        if errs:
            checks.append(check("log", "warn", f"{len(errs)} error line(s) in the shell log", False, "\n".join(errs[:5])))
        else:
            checks.append(check("log", "ok", "no errors in the recent shell log"))

    if shutil.which("taurus-core") and shells and shutil.which("busctl"):
        r = subprocess.run(["busctl", "--user", "list", "--no-legend"], capture_output=True, text=True)
        if "org.taurus.Core" in r.stdout:
            checks.append(check("core", "ok", "taurus-core is on the session bus"))
        else:
            checks.append(check("core", "warn", "taurus-core is installed but not on the session bus"))

    scene = os.path.join(state_dir(), "scene.json")
    if os.path.exists(scene):
        try:
            st = json.load(open(scene))
            name = st.get("active", "")
            known = [os.path.join(d, name + ".json") for d in (
                os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "taurus", "scenes"),
                os.path.join(TAURUS_DIR, "assets", "scenes"))]
            if name and not any(os.path.exists(k) for k in known):
                checks.append(check("scene", "warn", f"scene '{name}' is active but its file is gone", True))
        except (OSError, ValueError):
            checks.append(check("scene", "warn", "scene state is unreadable", True))
    return checks


# ---- repairs ----------------------------------------------------------------------------------------

def fix_settings():
    sp = settings_path()
    source = last_good() if parses(last_good()) else next((b for b in backups() if parses(b)), None)
    if not source:
        return None
    if os.path.exists(sp):
        shutil.copy2(sp, os.path.join(state_dir(), f"settings.broken.{int(time.time())}.json"))
    shutil.copy2(source, sp)
    return f"restored settings.json from {source}"


def apply_fixes(checks):
    actions = []
    for c in checks:
        if not c["fixable"] or c["status"] == "ok":
            continue
        if c["id"] == "settings":
            a = fix_settings()
            if a:
                actions.append(a)
        elif c["id"] == "daemon-files":
            for f in (pid_file(), lock_file()):
                try:
                    os.remove(f)
                    actions.append(f"removed {f}")
                except OSError:
                    pass
        elif c["id"] == "scene":
            subprocess.run([sys.executable, "-I", os.path.join(HERE, "scene.py"), "off"], capture_output=True)
            actions.append("undid the dangling scene")
    return actions


def write_recovery(kind, actions, restarted, detail=""):
    os.makedirs(state_dir(), exist_ok=True)
    with open(recovery_file(), "w") as f:
        json.dump({"time": int(time.time()), "kind": kind, "actions": actions, "restarted": restarted,
                   "detail": detail, "seen": False}, f, indent=2)


# ---- notifications --------------------------------------------------------------------------------------

def terminal_command():
    try:
        launcher = json.load(open(settings_path())).get("launcher", {})
    except (OSError, ValueError):
        launcher = {}
    term = shlex.split(launcher.get("terminalCommand", "")) if isinstance(launcher, dict) else []
    return term or ["kitty", "-e"]


def notify(summary, body):
    """Show a notification with a Diagnose button. Detached: the caller never waits for a click."""
    if not shutil.which("notify-send"):
        return False
    me = shlex.quote(os.path.join(HERE, "doctor.py"))
    script = (f'a=$(notify-send -a Taurus -u normal -t 0 -A diagnose=Diagnose {shlex.quote(summary)} {shlex.quote(body)}); '
              f'[ "$a" = diagnose ] && exec {shlex.quote(sys.executable)} -I {me} terminal')
    subprocess.Popen(["sh", "-c", script], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return True


def cmd_announce():
    try:
        r = json.load(open(recovery_file()))
    except (OSError, ValueError):
        return 0
    if r.get("seen"):
        return 0
    if r.get("kind") == "crash":
        summary = "Taurus recovered from a crash" if r.get("restarted") else "Taurus stopped unexpectedly"
    else:
        summary = "Taurus repaired a problem"
    body = "; ".join(r.get("actions") or []) or r.get("detail") or "Open Diagnose for the details."
    if notify(summary, body):
        r["seen"] = True
        with open(recovery_file(), "w") as f:
            json.dump(r, f, indent=2)
    return 0


def cmd_terminal():
    me = shlex.quote(os.path.join(HERE, "doctor.py"))
    bash = (f'{shlex.quote(sys.executable)} -I {me}; echo; '
            'if command -v claude >/dev/null 2>&1; then '
            'read -rp "Ask Claude Code to investigate with the taurus-diagnose skill? [y/N] " a; '
            '[ "$a" = y ] && exec claude "Use the taurus-diagnose skill to investigate why Taurus had a problem, and tell me what you find before changing anything."; '
            'fi; read -rp "Press Enter to close..." _')
    subprocess.Popen([*terminal_command(), "bash", "-c", bash], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


# ---- commands ---------------------------------------------------------------------------------------------

def cmd_report(args):
    checks = run_checks()
    actions = apply_fixes(checks) if "--fix" in args else []
    if actions:
        checks = run_checks()
    code = 2 if any(c["status"] == "fail" for c in checks) else 1 if any(c["status"] == "warn" for c in checks) else 0
    if "--json" in args:
        print(json.dumps({"checks": checks, "fixed": actions, "exit": code}, indent=2))
    else:
        icon = {"ok": "ok  ", "warn": "WARN", "fail": "FAIL"}
        for c in checks:
            print(f"{icon[c['status']]}  {c['message']}")
            if c.get("detail") and c["status"] != "ok":
                for line in c["detail"].splitlines():
                    print(f"      {line}")
            if c["fixable"] and c["status"] != "ok" and "--fix" not in args:
                print("      (fix with: taurus doctor --fix)")
        for a in actions:
            print(f"fixed: {a}")
    return code


def cmd_preflight():
    """Before the shell starts: a settings.json that does not parse is the commonest reason it never comes up."""
    checks = [c for c in run_checks() if c["id"] == "settings" and c["status"] == "fail"]
    actions = apply_fixes(checks)
    if actions:
        write_recovery("settings", actions, False)
        print("taurus: " + "; ".join(actions), file=sys.stderr)
    elif checks:
        write_recovery("settings", [], False, "settings.json is invalid and no backup could replace it")
    return 0


def cmd_recovered(rc):
    actions = apply_fixes(run_checks())
    write_recovery("crash", actions, True, f"the shell exited with status {rc}")
    return 0


def cmd_gave_up(rc):
    write_recovery("crash", [], False, f"the shell kept exiting (last status {rc}); not restarting again")
    print("taurus: the shell keeps exiting; giving up. Run: taurus doctor", file=sys.stderr)
    return 0


def cmd_mark_good():
    """Remember settings.json as 'known good' once it has proven itself: it parses, has been
    untouched for a minute, the shell is up and its log shows no new real errors."""
    sp = settings_path()
    shells = shell_pids()
    if not parses(sp) or time.time() - os.path.getmtime(sp) < 60 or not shells:
        return 0
    lines = log_lines(shells[0])
    if lines is not None and real_errors(lines):
        return 0
    os.makedirs(os.path.dirname(last_good()), exist_ok=True)
    shutil.copy2(sp, last_good())
    return 0


def main(argv):
    cmd = argv[0] if argv else ""
    rest = argv[1:]
    if cmd in ("", "--json", "--fix"):
        return cmd_report(argv)
    if cmd == "preflight":
        return cmd_preflight()
    if cmd == "recovered":
        return cmd_recovered(rest[0] if rest else "?")
    if cmd == "gave-up":
        return cmd_gave_up(rest[0] if rest else "?")
    if cmd == "mark-good":
        return cmd_mark_good()
    if cmd == "announce":
        return cmd_announce()
    if cmd == "terminal":
        return cmd_terminal()
    print("usage: taurus doctor [--json] [--fix]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
