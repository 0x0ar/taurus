---
sidebar_position: 3
title: Scenes
sidebar_label: Scenes
slug: /configure/scenes
---

# Scenes

A scene is a named bundle of settings that switch together: **do not disturb**, **dock and bar autohide**, **interface sounds**, **caffeine**, the **theme** and the **screen warmth**. Switch one by hand, or let Taurus switch it for you when a game is focused or the evening starts.

```bash
taurus scene list
taurus scene apply gaming
taurus scene off
```

Three scenes ship with Taurus: `work` (do not disturb, quiet), `gaming` (no interruptions, autohide, caffeine) and `night` (warm screen, quiet).

## What a scene changes, and how it undoes it

A scene is a JSON file with a fixed set of fields. There are no commands in it, so a scene someone shares with you can never run anything.

| Field | What it sets |
| --- | --- |
| `dnd` | Do not disturb. |
| `dock_autohide`, `bar_autohide` | Hide the dock or the bar until the pointer arrives. |
| `mute_sfx` | Interface sound effects. |
| `caffeine` | Keep the screen awake. |
| `theme` | A theme preset by name, or `matugen` to follow the wallpaper. |
| `gamma_temperature` | Screen warmth in kelvin, from 1000 to 10000. Needs `taurus-gamma`. Setting a temperature pauses the blue light filter's day and night schedule while the scene is active. Turning the scene off brings the schedule back with your own day and night temperatures, or your manual temperature if you had one. |

Applying a scene remembers what each field was. Turning it off puts a field back **only if it still holds what the scene wrote**: a value you changed in the meantime is kept. Switching from one scene to another restores the first before applying the second, so nothing leaks from one to the next.

Scene changes are not part of the settings backups, so switching scenes automatically never pushes your own backups out. Use `taurus scene off` to undo a scene, and `taurus config restore latest` to undo your own change.

## Automatic switching

Automatic switching is **off** until you turn it on:

```bash
taurus scene auto on
```

A scene can name the windows and the hours that activate it:

```json
{
  "name": "gaming",
  "dnd": true,
  "dock_autohide": true,
  "triggers": {
    "apps": ["steam_app_*", "gamescope", "lutris"],
    "time": {"from": "22:00", "to": "07:00"}
  }
}
```

- `apps` are window classes, with `*` as a wildcard. A matching focused window beats a matching time.
- `time` is a window of the day and may cross midnight, as in 22:00 to 07:00.
- The shell's own windows, such as the launcher, never end a scene.
- A scene you applied by hand is never overridden by the automatic ones, until you turn it off.

## Your own scenes

Put your files in `~/.config/taurus/scenes/<name>.json`. A scene of yours with the same name as a bundled one replaces it.

```bash
taurus scene save focus dnd mute_sfx theme   # capture the current values
taurus scene show focus
taurus scene delete focus
```

`taurus scene list` shows an invalid scene with the reason, and Taurus refuses to apply it.
