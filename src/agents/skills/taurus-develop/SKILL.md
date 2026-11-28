---
name: taurus-develop
description: Develop the Taurus desktop shell source code in a git checkout, for example adding a widget, a launcher tab, a settings option, a translation or a CLI command, and testing it safely. Use only when the user is working in the Taurus repository and asks to change the shell itself, not to customize their own setup.
---

# Developing Taurus

> **Priority rule: root via `pkexec`, never `sudo`.** When a command truly needs root (installing a package, writing under `/opt`, `/usr` or `/etc`), run it yourself with `pkexec` so polkit shows the user its own authentication dialog, for example `pkexec pacman -S --needed <package>`. Never use `sudo`, never ask the user for a password, and never ask them to run `sudo` themselves. Run one privileged command at a time and say what it does and why before you run it.

This skill is for a git checkout of the Taurus repository. If `taurus info paths --json` says `install_kind` is `package` or `user`, the install dir is not a place to edit: ask the user to work in a checkout.

## Layout

- `src/quickshell/`: the UI, in QML. One folder per area (`launcher/`, `bar/`, `dock/`, `lock/`, `widgets/`, `notifications/`, `guide/` for settings, `serp/` for the start screen). `Shell.qml` loads the windows; `Main.qml` has the IPC commands.
- `src/quickshell/singletons/`: shared state and controllers. QML types and singletons must be registered in `src/quickshell/qmldir` (or the folder's own `qmldir`).
- `src/scripts/`: shell scripts the UI and the CLI call. `bin/taurus` is the client and `bin/taurusd` the daemon.
- `src/assets/`: themes, languages (`languages/en.json`), shaders, fonts, `cli-commands.json`, `matugen/` app templates.
- `src/agents/skills/`: these skills. Keep them in sync with the CLI.
- `install/`: installer and its tests. `design/`: logo sources; `design/build_assets.sh` regenerates every logo derivative.

## Conventions

- All user-visible text goes through `I18n.t("section.key", "English default")`. Add the key to `src/assets/languages/en.json` (and `es.json` if you can); other languages fall back to English.
- Colors come from `ThemeBackend` (never hard-coded), sizes from the existing scaling helpers.
- New shell commands go in `bin/taurus` and in `src/assets/cli-commands.json` with a risk level (`read`, `change`, `disruptive`). The test `install/tests/cli_agent_test.sh` fails when they drift apart.
- Docs for users live in `docs/`. The guides inside `src/agents/skills/taurus/references/` are generated from them: run `python3 tools/sync-skill-docs.py` after editing `docs/`.

## Adding things (follow an existing example)

- **Launcher tab:** the Packages tab in `src/quickshell/launcher/Launcher.qml` touches every place a tab is mentioned: tab title property, `currentTabIndex` branches, debounce timer, the tab switch options, `Tab` and `Backtab` modulo, placeholder, the model item fields, and the activation handler. Search for `pkgName` to find them all.
- **Widget:** add `widgets/faces/<name>/<Name>Face.qml`, register the face in `widgets/faces/qmldir`, and add a type entry in `widgets/WidgetRegistry.qml`. `widgets/faces/bull/` is a small complete example.
- **Setting:** add the option to the settings UI under `guide/`, read it with `Config.getSetting`, add the default to `config/taurus/settings.json`, and document it in `docs/configure/Configure.md`.

## Testing without touching the user's session

Never test against the user's running shell or compositor, and do not run `taurus ...` commands that start `taurusd` from a checkout on their real session.

- Lint: `/usr/lib/qt6/bin/qmllint <file.qml>`. Shell: `bash -n`. Python: `python3 -m py_compile`.
- Run the installer tests: `bash install/tests/*_test.sh` and `python3 -I install/tests/tui_test.py`.
- Run the real shell headless: start `umbriel` with `WLR_BACKENDS=headless WLR_RENDERER=pixman` in a private `XDG_RUNTIME_DIR` (keep the path short, a long one breaks the Quickshell IPC socket) under `dbus-run-session`, then run `quickshell -p src/quickshell/Shell.qml` with `TAURUS_DIR`, `QS_SETTINGS`, `QS_STATE_DIR` and `QS_CACHE_DIR` pointing at a temporary HOME. Take screenshots with `grim`. Control it through `quickshell -p src/quickshell/Shell.qml ipc call main handleCommand open launcher ""`.
- Say plainly what you did not test (for example typing into a window, or installing packages).
