---
sidebar_position: 5
title: Share your setup
sidebar_label: Share your setup
slug: /configure/share
---

# Share your setup

Export what makes your Taurus yours into **one file**, send it to someone, and let them preview and import it.

```bash
taurus share export -o my-setup.json
taurus share import their-setup.json          # preview only, nothing changes
taurus share import their-setup.json --apply  # apply it
```

## What is in the file

- The settings you **changed** from the defaults, not the whole settings file.
- Your own **themes** (`~/.local/state/taurus/themes/`) and **scenes** (`~/.config/taurus/scenes/`).
- Your widget **layouts**: position, size, type and variant of each widget.

## What never leaves your machine

Export leaves out anything personal or specific to your machine, and tells you exactly what it skipped:

- Your avatar, location, anything that looks like a token, key, password or e-mail, and any value that holds a file path.
- Your monitors, the apps pinned in your dock, the notification sound file, do not disturb and other runtime state.
- Text, images and lists inside widgets (notes, GitHub names, photos). Only position, size and simple numbers and switches stay.
- Wallpapers, and the Matugen overrides that edit other apps' config files.

Read the file before you send it: it is plain JSON.

## Importing a file from someone else

A setup file is **untrusted**, so importing is careful by design.

- **Preview first.** `taurus share import FILE` only shows what would change, and what it ignored and why. Add `--apply` to apply it. A backup of your settings is made first, so `taurus config restore latest` undoes it.
- **Only real options.** A setting is applied only if it exists in the shipped defaults with the same type, and is small plain data. Unknown or wrongly typed values are ignored, not fatal.
- **Themes** must have all the color roles as `#rrggbb`. A theme named like a bundled one is renamed with `-shared`, so it never hides it. One you already have is skipped unless you pass `--overwrite`.
- **Scenes** go through the same closed schema as your own: they contain no commands, so a shared scene cannot run anything.
- **Layouts replace yours**, so they are opt-in: add `--layouts`. Your current layout is kept as `layout.json.bak`, and only monitors with the same name as yours are touched.
- Files larger than 1 MB, or not made by `taurus share`, are refused.
