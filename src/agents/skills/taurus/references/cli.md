<!-- Generated from docs/cli/client.md by tools/sync-skill-docs.py. Do not edit. -->

# Taurus client

`taurus` is the command-line client for the desktop shell.

## Overview

| Command | Purpose |
| --- | --- |
| `msg` | Open, close or toggle panels and switch workspaces. |
| `settings` | Open the settings window, optionally on a given tab. |
| `launch` | Run standalone components such as the setup wizard or the layout editors. |
| `config` | Read and write raw settings. |
| `info` | Print the current state of a setting. |
| `set` | Change a setting. |
| `trigger` | Run a one-off action. |
| `share` | Export your setup to one file, or preview and import another. |
| `doctor` | Check why the shell may not run, and repair the safe things. |
| `scene` | Switch scenes: named bundles of settings. |
| `commands` | List every command with its usage and risk level. |
| `agent` | Install or remove the AI agent skills. |
| `ipc` | Send raw IPC calls to the running shell. |
| `kill`, `restart` | Stop or restart the daemon. |
| [Script shortcuts](#script-shortcuts) | Wrappers around the bundled scripts, such as `lock`, `volume` or `reboot`. |

## Options

- `-v, --verbose`: Enable verbose logging output.
- `-V, --version`: Print installed version and exit.
- `-h, --help`: Show usage help and exit.

## Commands

### `msg`

Dispatches layout, workspace, and overlay actions to the shell:

- `taurus msg workspace <number>`: Switch to workspace `<number>`.
- `taurus msg workspace <number> move`: Move active window to workspace `<number>`.
- `taurus msg <number>`: Shorthand to switch to workspace `<number>`.
- `taurus msg <number> move`: Shorthand to move active window to workspace `<number>`.
- `taurus msg open <target> [subtarget]`: Open a panel or activate a subtab.
- `taurus msg toggle <target> [subtarget]`: Toggle panel visibility.
- `taurus msg close`: Close any open overlay.
- `taurus msg notifications clear`: Clear all notifications.
- `taurus msg network airplane`: Toggle airplane mode (WiFi and Bluetooth).
- `taurus msg bar autohide`: Toggle bar autohide live.

#### Targets

- `launcher`: Application search and launcher overlay.
- `clipboard` (alias: `clip`): Clipboard history manager.
- `network`: Network manager popup.
  - `network wifi`: Open directly on WiFi tab.
  - `network ethernet`: Open directly on Ethernet tab.
- `volume`: Audio mixer and device picker.
- `settings`: Settings panel or window (same as [`taurus settings`](#settings)).
  - `settings keybinds`: Open shortcut cheat sheet tab.
  - `settings appearance`: Open appearance and styling tab.
  - `guide` is a deprecated alias for `settings` and prints a warning.
- `calendar`: Calendar, clock, and schedule panel.
- `music`: Media player controls and track artwork.
- `wallpaper`: Wallpaper picker and live preview.
- `notifications`: Notification history center.
- `system`: System resource monitor and power controls.

### `settings`

Opens the settings as a panel inside the shell, like other popups.

- `taurus settings`: Open the settings.
- `taurus settings <tab> [subtab]`: Open directly on a tab, for example `taurus settings theme`.
- `taurus settings toggle [tab]`: Close the settings if they are open, otherwise open them.
- `taurus settings close`: Close the settings.

### `launch`

Runs standalone interface components in runner mode:

- `taurus launch start [args...]`: Launch first-time setup and onboarding wizard.

### `ipc`

Sends raw IPC calls directly to the running shell:

- `taurus ipc call <target> <method> [args...]`: Forward call to target object.
  - `ipc call main handleCommand <cmd> <target> <arg>`: Dispatch generic UI command.
  - `ipc call main forceReload`: Force reload shell components.
  - `ipc call main clearNotifications`: Purge all notification popups and history.
  - `ipc call lock activate`: Trigger lock screen immediately.
  - `ipc call screenshotOverlay toggle [args...]`: Toggle interactive screenshot overlay.
  - `ipc call floating toggle`: Open the quick actions panel on the last used tab, or close it if it is open on any screen. Bind it to a key in your compositor, e.g. Hyprland: `hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("taurus ipc call floating toggle"))`.
  - `ipc call floating open` / `close`: Open the panel on the screen under the cursor, or close it on every screen. Opened this way, it stays until closed, Escape is pressed, or the pointer enters and leaves it.

### `share`

Exports your setup and imports someone else's. See Share your setup.

- `taurus share export [-o FILE|-]`: Write your changed settings, themes, scenes and layouts to a file (default `taurus-setup.json`, `-` for standard output). Personal and machine-specific data is left out and reported.
- `taurus share import FILE`: Preview what a file would change. Nothing is written.
- `taurus share import FILE --apply`: Apply it. Your settings are backed up first.
- `--overwrite`: Replace themes and scenes you already have. `--layouts`: Also replace your widget layouts (the old file is kept).

### `doctor`

Checks what keeps the shell from running: the settings file, the daemon files, the shell process, its log and the companion services. See Self-healing.

- `taurus doctor [--json]`: Report. It only reads. Exit status 0 means all good, 1 warnings, 2 failures.
- `taurus doctor --fix`: Also apply the safe repairs: restore a `settings.json` that does not parse, remove stale pid files, undo a dangling scene.

### `scene`

Switches scenes:

- `taurus scene list [--json]`: List the scenes. The active one is marked.
- `taurus scene show <name>`: Print a scene.
- `taurus scene apply <name>`: Apply a scene by hand. Automatic switching leaves it alone.
- `taurus scene off`: Undo the active scene. Values you changed meanwhile are kept.
- `taurus scene status [--json]`: Show the active scene and whether automatic switching is on.
- `taurus scene save <name> [fields...]`: Save the current values as a scene of your own.
- `taurus scene delete <name>`: Delete a scene of your own.
- `taurus scene auto <on|off|status>`: Turn automatic switching (by focused app and time) on or off.

### `commands`

Lists every command with its usage and a risk level, so a person or an AI agent can discover the whole CLI:

- `taurus commands`: Print a table.
- `taurus commands --json`: Print the registry as JSON.

The risk levels are `read` (only reads state), `change` (changes settings or UI state, reversible) and `disruptive` (interrupts the session, locks or powers off the machine, or restarts the shell). `commands` never starts the shell.

### `agent`

Manages the AI agent skills:

- `taurus agent skills install [--force-path]`: Link the Taurus skills into `~/.claude/skills` (or `$CLAUDE_CONFIG_DIR/skills`) and `~/.agents/skills`, plus the skills folder of Codex (`~/.codex/skills`), Gemini CLI (`~/.gemini/skills`) and OpenCode (`~/.config/opencode/skills`) when they are installed. A skill folder of your own with the same name is never replaced. It refuses to link from a cache folder or a git checkout unless you pass `--force-path`.
- `taurus agent skills uninstall`: Remove only the links Taurus created.
- `taurus agent skills status [--json]`: Show what is linked.

### `kill`

Stops the daemon and terminates all background shell workers (`taurus-core screentime track`, `quickshell`, `taurusd`).

### `restart`

Stops the daemon and starts it again.

## Settings and state

### `config`

Reads and writes `settings.json`. Keys use dots to reach nested values and changes apply live:

- `taurus config get <key> [fallback]`: Print a setting.
- `taurus config set <key> <value>`: Set a setting. Values are parsed as JSON and fall back to plain strings.
- `taurus config dump`: Print the whole settings file.
- `taurus config path`: Print the settings file path.
- `taurus config edit`: Open the settings file in `$VISUAL` or `$EDITOR`.
- `taurus config reset <key>`: Restore a key to the value shipped with the install, or remove it when there is no shipped default.
- `taurus config diff`: Show what you changed compared with the shipped defaults.
- `taurus config backup`: Back up the settings now.
- `taurus config backups`: List the backups, newest first.
- `taurus config restore [file|latest]`: Restore a backup. It backs up the current file first.

Every write made through `taurus` (`config set`, `config reset`, `set ...`) first copies the settings file to `~/.local/state/taurus/backups/` and keeps the newest 20. `config set` warns, without blocking, when a key is not in the shipped defaults, which usually means a typo.

### `info`

Prints the current state of a group as JSON. Add a key to print just that value, for example `taurus info dock autohide`. Lists print one item per line:

- `taurus info notifications [dnd]`: Do not disturb.
- `taurus info idle [key]`: Idle system state: whether idle is active, caffeine and its seconds remaining (`0` when it has no time limit), app and media inhibitors, and each action's timeout and status.
- `taurus info dock [enabled|autohide]`: Dock visibility and autohide.
- `taurus info sfx [mute]`: Interface sound effects muted.
- `taurus info theme [preset|matugen|apps|presets]`: Active preset, wallpaper-derived colors, apps that follow the palette and the available presets (bundled and your own).
- `taurus info lang [current|available]`: Active language code and available codes.
- `taurus info wallpaper [screen]`: Current wallpaper path.
- `taurus info monitors [--json]`: Active outputs, with width, height and refresh rate as JSON.
- `taurus info updates [--json]`: Installed version compared with the latest release.
- `taurus info paths [--json]`: Where things are: install dir (and whether it is read-only), settings, shipped defaults, backups, state, cache, logs, your own themes and the bundled ones.

### `set`

Changes a setting. Switches take `on`, `off` or `toggle` and default to `toggle`:

- `taurus set notifications dnd [on|off|toggle]`
- `taurus set idle caffeine [on|off|toggle]`
- `taurus set dock enabled [on|off|toggle]`
- `taurus set dock autohide [on|off|toggle]`
- `taurus set sfx mute [on|off|toggle]`
- `taurus set theme matugen [on|off|toggle]`
- `taurus set theme preset <name>`: Apply a preset, bundled or your own from `~/.local/state/taurus/themes/`, and turn Matugen off.
- `taurus set theme app <id> [on|off|toggle]`: Recolor an app with the shell palette. See App theming.
- `taurus set lang <code>`
- `taurus set wallpaper <path|random|next|prev|play|pause|clear> [screen]`: `screen` is a monitor name and defaults to `all`. A path may also take a transition after the screen.

### `trigger`

Runs a one-off action:

- `taurus trigger idle <dim|dpms|lock|suspend>`: Run an idle action now.
- `taurus trigger notifications clear`: Clear all notifications.
- `taurus trigger firstlaunch <trigger|reset>`: Run or reset the first launch setup.
- `taurus trigger theme reload`: Reload colors.
- `taurus trigger theme generate <image> [mode] [scheme]`: Generate colors from an image.

## Script shortcuts

### `screenshot`

Captures screen images, records video, or decodes QR codes:

- `taurus screenshot`: Open interactive selection and recording overlay.
- `taurus screenshot --full`: Capture focused monitor immediately.
- `taurus screenshot --edit`: Open screenshot in Satty image editor.
- `taurus screenshot --record`: Toggle screen video recording (start or stop).
- `taurus screenshot --scan-qr`: Scan selected region for QR codes.
- `taurus screenshot --color-picker`: Open the screen color picker directly.
- `taurus screenshot --geometry <X,Y WxH>`: Set capture crop region.
- `taurus screenshot --monitor <name>`: Set target monitor output.
- `taurus screenshot --backend <gpu-screen-recorder|wf-recorder>`: Set recording backend.
- `taurus screenshot --desk-vol <0.0-1.0>`: Set desktop audio volume multiplier.
- `taurus screenshot --desk-mute <true|false>`: Mute desktop audio in recording.
- `taurus screenshot --mic-vol <0.0-1.0>`: Set microphone audio volume multiplier.
- `taurus screenshot --mic-mute <true|false>`: Mute microphone audio in recording.
- `taurus screenshot --mic-dev <name>`: Set microphone input device name.

### `colorpicker`

Opens the screen color picker directly on the focused monitor:

- `taurus colorpicker`: Pick a pixel color and copy it to the clipboard.
- `taurus colorpicker --monitor <name>`: Open the color picker on a specific monitor output.

### `volume`

Controls audio sink and source levels via WirePlumber:

- `taurus volume raise`: Increase output volume by 5%.
- `taurus volume lower`: Decrease output volume by 5%.
- `taurus volume mute-toggle`: Toggle output mute.
- `taurus volume mic-toggle`: Toggle microphone mute.
- `taurus volume mic-raise`: Increase microphone volume by 5%.
- `taurus volume mic-lower`: Decrease microphone volume by 5%.

### `brightness`

Controls display backlight and external monitor brightness:

- `taurus brightness get`: Print current brightness percentage (default).
- `taurus brightness set <0-100>`: Set brightness to percentage.
- `taurus brightness raise`: Increase brightness by 5%.
- `taurus brightness lower`: Decrease brightness by 5%.
- `taurus brightness backend`: Print active backend (`backlight`, `ddc`, or `none`).
- `taurus brightness watch`: Watch backlight changes with inotify.

### `weather`

Queries weather data and manages forecast cache:

- `taurus weather --current-temp`: Print current temperature.
- `taurus weather --current-icon`: Print current weather icon glyph.
- `taurus weather --current-hex`: Print current weather condition accent hex.
- `taurus weather --temp`: Print today forecasted maximum temperature.
- `taurus weather --icon`: Print today forecast icon glyph.
- `taurus weather --hex`: Print today forecast accent hex.
- `taurus weather --json`: Print complete structured forecast JSON.
- `taurus weather --getdata`: Force fresh fetch from Open-Meteo API.
- `taurus weather --nav next`: Advance 5-day forecast view to next day.
- `taurus weather --nav prev`: Move 5-day forecast view to previous day.
- `taurus weather --view-listener`: Stream active forecast view index.
- `taurus weather --unit <metric|imperial|standard>`: Set temperature unit profile.
- `taurus weather --location '<json>'`: Pass custom coordinates JSON.
- `taurus weather --verbose` (`-v`): Print verbose debug output.

### `location`

Retrieves and updates geographic coordinates:

- `taurus location`: Print cached or retrieved location JSON.
- `taurus location --refresh` (`-r`): Force fresh lookup from IP geolocation providers.
- `taurus location --verbose` (`-v`): Print debug diagnostics to stderr.

### `location_manual`

Sets geographic coordinates manually:

- `taurus location_manual <latitude> <longitude>`: Set coordinates, reverse-geocode city and country, resolve timezone, and save to settings.

### `gamma`

Controls color temperature and the day/night schedule through [taurus-gamma](https://github.com/0x0ar/taurus-gamma), which it starts when needed. Taurus stops it on exit, and the compositor then restores normal colors.

- `taurus gamma set <temperature> [output] [mode] [latitude] [longitude]`: Set temperature (1000-10000K) manually (`mode=manual`), or use it as the night temperature of the solar schedule (`mode=auto`). Without coordinates, or with `0 0`, the schedule fades to night at 19:00 and to day at 06:30. Without an output, every output is changed.
- `taurus gamma reset [output]`: Reset color temperature to 6500K daylight neutral and turn the schedule off.
- `taurus gamma status [output]`: Print status (`running` or `stopped`).
- `taurus gamma start`: Start taurus-gamma if it is not running.
- `taurus gamma stop`: Stop taurus-gamma.
- `taurus gamma --verbose` (`-v`): Print verbose output with current Kelvin, brightness and schedule state.

### `lock`

Activates lock screen:

- `taurus lock`: Trigger lock screen interface immediately.

### `redactor`

Opens the desktop widget layout editor in the running shell:

- `taurus redactor`: Open the editor.
- `taurus redactor <monitor> [widget]`: Open the editor on a monitor, optionally with a widget selected.

### `lock-redactor`

Opens the lock screen layout editor in the running shell:

- `taurus lock-redactor`: Close the editor if it is open, otherwise open it.
- `taurus lock-redactor open [monitor]`: Open the editor, optionally on a given monitor.
- `taurus lock-redactor close`: Close the editor.

### `reload`

Reloads shell:

- `taurus reload`: Force reload QuickShell desktop elements without restarting the daemon.

### `exit`

Terminates desktop session:

- `taurus exit`: Cleanly terminate graphical session and exit active compositor.

### `suspend`, `hibernate`, `reboot`, `poweroff`

- `taurus suspend`: Lock the screen and suspend the system.
- `taurus hibernate`: Hibernate the system.
- `taurus reboot`: Reboot the system.
- `taurus poweroff`: Power off the system.

## Keybinding examples

Panels and workspaces go through `msg`, everything else through `set`, `trigger` or the script shortcuts:

```
taurus msg toggle launcher
taurus msg toggle clipboard
taurus msg toggle calendar
taurus set notifications dnd toggle
taurus set wallpaper random
taurus set idle caffeine toggle
taurus trigger notifications clear
taurus volume raise
taurus screenshot --full
```
