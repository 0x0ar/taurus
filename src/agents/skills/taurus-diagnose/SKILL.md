---
name: taurus-diagnose
description: Diagnose problems with the Taurus desktop shell, such as the shell not starting, a missing bar, popup or widget, a crash, a broken setting, or a failing companion service (taurus-core, taurus-gamma, taurus-audio). Use when the user says Taurus is broken, frozen, blank, slow, or shows errors.
---

# Diagnosing the Taurus shell

> **Priority rule: root via `pkexec`, never `sudo`.** When a command truly needs root (installing a package, writing under `/opt`, `/usr` or `/etc`), run it yourself with `pkexec` so polkit shows the user its own authentication dialog, for example `pkexec pacman -S --needed <package>`. Never use `sudo`, never ask the user for a password, and never ask them to run `sudo` themselves. Run one privileged command at a time and say what it does and why before you run it.

Collect evidence first and change nothing until you know the cause. Do not restart the shell, run `taurus kill` or `taurus restart`, or reload anything before reading the logs: a restart destroys the evidence and is a `disruptive` command that needs the user's approval.

## 1. Snapshot

```sh
taurus doctor --json                  # read-only: settings, daemon files, shell, log errors, services
taurus --version
taurus info paths --json              # log_dir, state_dir, settings, install kind
pgrep -a quickshell; pgrep -a taurusd
cat /tmp/taurusd.pid 2>/dev/null      # daemon pid file
```

If nothing is running, say so; do not start it yet.

## 2. Logs

Quickshell writes its own log for every run (a line such as "Saving logs to .../quickshell/by-id/<id>/log.qslog" appears at startup).

```sh
pgrep -f "quickshell.* -p .*quickshell/Shell.qml"    # the pid of the Taurus shell
quickshell log --pid <pid> --tail 200                # select the instance by pid
```

Always select the instance with `--pid`: a bare `quickshell log` looks for a "default" config, finds none, or reads another shell's log if two run side by side. `taurus doctor` already does this. The raw files are `$XDG_RUNTIME_DIR/quickshell/by-id/*/log.qslog`.

Look for lines marked ERROR first, then WARN. Typical findings:

- `Type X unavailable` or a `ReferenceError`/`TypeError`: a QML file is broken. Note the file and line.
- `Failed to connect pipewire context`: PipeWire is not running (audio widgets only).
- `No PanelWindow backend loaded`: the compositor lacks layer-shell, or the shell runs outside a Wayland session.
- A polkit "agent already exists" warning is harmless: another agent owns it.

The folder `log_dir` from `taurus info paths` holds widget logs when a widget writes any.

## 3. Companion services

```sh
taurus-core --version
busctl --user list | grep org.taurus       # org.taurus.Core and org.taurus.Gamma on the session bus
taurus-gamma status
taurus-audio ctl status
```

A missing bus name means that service is not running. `taurus-core` is started on demand by D-Bus; if it is absent and the shell is up, check that `TAURUS_DIR` reaches it (the daemon exports it).

## 4. Settings

`taurus doctor --fix` repairs a `settings.json` that does not parse (from the last known good copy or a backup), removes stale daemon files and undoes a dangling scene. It never restores settings for a QML error. It changes files, so ask the user first.


```sh
jq . "$(taurus config path)" >/dev/null && echo "settings.json is valid JSON"
taurus config diff            # what the user changed
taurus config backups
```

If a recent change broke the shell, `taurus config restore latest` undoes the last write (ask first).

## 5. Report

Give the user: what is running, the first ERROR lines with file and line, the most likely cause, and a proposed fix with how to undo it. Offer the disruptive steps (restart, reload) as options; do not run them unasked. To report a bug upstream, include `taurus --version`, the install kind and the ERROR lines.
