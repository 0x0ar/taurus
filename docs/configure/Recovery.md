---
sidebar_position: 4
title: Self-healing
sidebar_label: Self-healing
slug: /configure/recovery
---

# Self-healing

Taurus checks itself and repairs the few things that can be repaired safely. Nothing here needs you to do anything; this page explains what happens and how to check it by hand.

## Check by hand

```bash
taurus doctor            # report: settings, daemon files, shell, log, services
taurus doctor --json
taurus doctor --fix      # also apply the safe repairs below
```

`taurus doctor` exits with 0 when all is well, 1 for warnings and 2 for failures. Without `--fix` it only reads.

## What it repairs, and what it never does

| Problem | Repair |
| --- | --- |
| `settings.json` is not valid JSON | Restores the last known good copy, or the newest backup that parses. The broken file is kept next to it as `settings.broken.<time>.json`. |
| Stale daemon pid or lock files | Removes them. |
| An active scene whose file is gone | Undoes the scene. |

It **never restores your settings because of a QML error** in the log: that is a bug in the code, and restoring would throw away valid changes of yours. It reports those errors and leaves the decision to you.

## Before the shell starts

The daemon checks `settings.json` before it launches the shell. A file that does not parse is the commonest reason the shell never comes up, and it is repaired from the last known good copy first.

A copy becomes the *last known good* once the settings have been untouched for a minute, the shell is running and its log shows no new errors. It is stored in `~/.local/state/taurus/last-good/`, apart from the backups.

## If the shell crashes

The daemon restarts the shell **once**. It does not restart when the shell exits cleanly, when you stop it with `taurus kill`, or when your session has ended (it waits a moment and checks again, so a logout is not mistaken for a crash). Anything that kills the shell from outside, such as `pkill quickshell`, counts as a crash and gets one restart: use `taurus kill` to stop the shell on purpose. The crashed shell's leftover helper processes are ended before the restart. If a restarted shell dies again within 20 seconds, or the shell has been restarted twice in ten minutes, the daemon stops instead of looping.

Because the shell is also the notification server, nothing can be shown while it is down. Once it is running again, a notification tells you what happened, with a **Diagnose** button. The button opens a terminal with the `taurus doctor` report and, if Claude Code is installed, offers to investigate with the `taurus-diagnose` skill. It asks before doing anything. If the shell could not be restarted, the same notification appears the next time it starts.
