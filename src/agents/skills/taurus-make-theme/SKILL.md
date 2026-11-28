---
name: taurus-make-theme
description: Create or edit a color theme preset for the Taurus desktop shell, or customize how Taurus recolors other apps. Use when the user wants a new Taurus color scheme, a theme based on a palette or wallpaper, or to tweak a built-in app theme template for Taurus.
---

# Making a Taurus theme

> **Priority rule: root via `pkexec`, never `sudo`.** When a command truly needs root (installing a package, writing under `/opt`, `/usr` or `/etc`), run it yourself with `pkexec` so polkit shows the user its own authentication dialog, for example `pkexec pacman -S --needed <package>`. Never use `sudo`, never ask the user for a password, and never ask them to run `sudo` themselves. Run one privileged command at a time and say what it does and why before you run it.

A theme is one JSON file. Taurus keeps bundled presets in the install dir (read-only) and the user's own in a separate folder, so a custom theme never edits a bundled one.

## Where things are

Run `taurus info paths --json` and use:

- `bundled_themes`: bundled presets (read only, good as a starting point).
- `user_themes`: put the new theme here as `<Name>.json`. Create the folder if it is missing.
- `user_matugen_apps`: per-app template overrides (see the end).

## File format

Copy a bundled preset that is close to what the user wants, then change the colors. Shape:

```json
{
  "name": "MyTheme",
  "isColorFocused": true,
  "colors": {
    "base": "#000000", "mantle": "#000000", "crust": "#000000",
    "text": "#e3f5ea", "subtext0": "#a8c7b4", "subtext1": "#c4e0cf",
    "surface0": "#0c140f", "surface1": "#14201a", "surface2": "#1e2f25",
    "overlay0": "#3f6650", "overlay1": "#538068", "overlay2": "#6a9c80",
    "blue": "#00e676", "sapphire": "#00bd61", "peach": "#b2f5c8", "green": "#00e676",
    "red": "#ff6b6b", "mauve": "#33eb91", "pink": "#8af5c0", "yellow": "#d4f56a",
    "maroon": "#ff9d9d", "teal": "#5cf0a8"
  }
}
```

Roles: `base`, `mantle`, `crust` are backgrounds (from lightest to darkest in a dark theme); `text`, `subtext0`, `subtext1` are foregrounds; `surface0..2` and `overlay0..2` are raised surfaces and muted UI; `blue` is the primary accent, `mauve` the secondary; the rest are semantic or decorative accents (`red` for errors, `green` for success). All 22 keys are expected, as `#rrggbb`.

## Procedure

1. Pick the base preset: `taurus info theme presets`, then read the file from `bundled_themes`.
2. Write `<user_themes>/<Name>.json`. Keep `name` equal to the file name (without `.json`).
3. Validate: `jq -e '.colors | length == 22' <file>`.
4. Check contrast: `text` on `base` should reach at least 4.5:1, and accent colors should stay readable on `surface0`.
5. Apply: `taurus set theme preset <Name>`. The shell updates live. Show the user the result and ask before keeping it.
6. To undo: `taurus set theme preset Taurus`, or `taurus config restore latest`.

For a palette that follows a wallpaper instead, use Matugen: `taurus set theme matugen on`, or `taurus trigger theme generate <image>`.

## Recoloring other apps

Apps are themed from templates. Only the built-in apps can be customized: copy the app folder from `bundled_matugen_apps` to `<user_matugen_apps>/<app>/` and edit it there (the folder name must match the built-in one; other names are ignored). Never edit the bundled templates. Details: the app theming guide in the `taurus` skill, [../taurus/references/app-theming.md](../taurus/references/app-theming.md).
