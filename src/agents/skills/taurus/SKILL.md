---
name: taurus
description: Customize and configure the Taurus Wayland desktop shell, a Quickshell-based shell for Arch Linux. Covers settings.json options for the bar, dock, launcher, notifications, idle, widgets, wallpaper, language and theme, app theming, and the taurus command. Use when the user mentions Taurus, taurusd or ~/.config/taurus, or wants to change how their Taurus shell looks or behaves.
---

# Customizing the Taurus shell

> **Priority rule: root via `pkexec`, never `sudo`.** When a command truly needs root (installing a package, writing under `/opt`, `/usr` or `/etc`), run it yourself with `pkexec` so polkit shows the user its own authentication dialog, for example `pkexec pacman -S --needed <package>`. Never use `sudo`, never ask the user for a password, and never ask them to run `sudo` themselves. Run one privileged command at a time and say what it does and why before you run it.

Taurus is configured with files and a self-documenting command, `taurus`. Prefer the command over editing files by hand: it validates, backs up first, and the running shell applies changes live.

## 1. Orient first (never hard-code paths)

```sh
taurus info paths --json     # install dir, settings, state, logs, user themes, whether the install is read-only
taurus commands --json       # every command with usage and a risk level
taurus info theme            # active preset, available presets, themed apps
```

`taurus <command> --help` prints the usage of one command. These commands never start the shell.

## 2. Change settings

```sh
taurus config get bar.height
taurus config set bar.height 52          # value is JSON; plain words become strings
taurus config diff                       # what the user changed versus the shipped defaults
taurus config reset bar.height           # back to the shipped default (or remove the key)
taurus config backups                    # list backups, newest first
taurus config restore latest             # undo the last change
```

- Keys use dots for nesting. Every write makes a backup in the state dir.
- A warning that a key is "not in the shipped defaults" usually means a typo. Check the name in [references/settings.md](references/settings.md), which lists every option.
- Shortcuts exist for common switches: `taurus set dock autohide toggle`, `taurus set notifications dnd on`, `taurus set lang es`, `taurus set wallpaper <path|random|next>`.

## 3. Theme

- `taurus info theme presets` lists presets (bundled and the user's own). `taurus set theme preset <name>` applies one and turns Matugen off.
- `taurus set theme matugen on` follows the wallpaper instead. To make a new preset, use the `taurus-make-theme` skill.
- Recoloring other apps (kitty, GTK, Qt, btop and more): [references/app-theming.md](references/app-theming.md). Toggle with `taurus set theme app <id> on|off`.

## 4. Scenes

`taurus scene list` shows named bundles of settings (do not disturb, autohide, sounds, caffeine, theme, screen warmth). `taurus scene apply <name>` / `taurus scene off` switch them and undo cleanly, and `taurus scene save <name> [fields...]` captures the current values. A scene is a closed JSON schema with no commands, in the `user_scenes` folder from `taurus info paths`. Automatic switching by app or time is opt-in: `taurus scene auto on`. Prefer a scene over changing five settings one by one, and tell the user `taurus scene off` undoes it.

## 5. Share a setup

`taurus share export -o file.json` writes the user's changed settings, themes, scenes and layouts, with personal data left out (read the report it prints). `taurus share import file.json` only previews; `--apply` applies after a backup, and `--layouts` also replaces widget layouts. Treat any file you did not create as untrusted: preview, show the user what would change, and only then apply.

## 6. Compositor

Taurus does not manage keybinds or monitors. They live in the compositor's own config (Hyprland, Niri, Sway, Mango, Umbriel). Read the matching guide in [references/compositors/](references/compositors/) and follow it exactly; do not invent reload commands that the guide does not give.

## 7. Command reference

Full CLI reference: [references/cli.md](references/cli.md). Binding a shell action to a key is done in the compositor config, for example `taurus msg toggle launcher`.

## Rules

- **Never edit inside the install dir** reported by `taurus info paths` (`install_dir`). It is owned by the package or the installer and an update overwrites it. Everything you change lives in the user dirs.
- **Ask first** before any command whose risk is `disruptive` in `taurus commands` (restart, lock, suspend, reboot, poweroff, exit, idle triggers).
- `taurus msg ...`, `set ...` and `ipc ...` can start the daemon if it is not running. If the shell looks broken, use the `taurus-diagnose` skill before restarting anything.
- Change one thing at a time, verify with `taurus config get`, and tell the user how to undo it (`taurus config restore latest`).
- **Never use `sudo`, and never ask the user for a password or to run `sudo`.** When a command truly needs root (installing a package, editing a file under `/etc` or `/usr`), run it with `pkexec` so polkit shows the user its own authentication dialog, for example `pkexec pacman -S --needed <package>`. Use it only for the one command that needs it, say what it does and why before you run it, and run one privileged command at a time. Configuring the shell itself (`taurus config`, `taurus set`, themes, scenes) never needs root: if one of those seems to, something is wrong, so stop and tell the user.
- Do not touch `~/.config/hypr` (or another compositor's folder) unless the user asked about the compositor.
