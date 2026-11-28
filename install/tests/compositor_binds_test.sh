#!/usr/bin/env bash
# The wheel binds added in 68290af must reach configs that predate the commit,
# without clobbering user edits or duplicating the block on repeated installs.

set -u

REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

failures=0
check() {
    if eval "$2"; then
        echo "ok    $1"
    else
        echo "FAIL  $1"
        failures=$((failures + 1))
    fi
}

export HOME="$SANDBOX/home"
t() { printf '%s' "$1"; }
# shellcheck disable=SC1090
source "$REPO_ROOT/install/modules/compositor_binds.sh"

mkdir -p "$HOME/.config/niri/config"
cat > "$HOME/.config/niri/config/keybinds.kdl" <<'EOF'
binds {
    Mod+Return { spawn "kitty"; }
    Mod+Q { close-window; }
}
EOF

ensure_compositor_binds niri >/dev/null
NIRI="$HOME/.config/niri/config/keybinds.kdl"
check "niri: wheel binds are added" \
    'grep -Fq "Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }" "$NIRI" && grep -Fq "Mod+WheelScrollLeft cooldown-ms=150 { focus-column-left; }" "$NIRI"'
check "niri: binds stay inside the binds block" \
    '[ "$(tail -n 1 "$NIRI")" = "}" ]'
check "niri: a backup of the old config is kept" \
    'ls "$NIRI".taurus-bak.* >/dev/null 2>&1'

before=$(wc -l < "$NIRI")
ensure_compositor_binds niri >/dev/null
check "niri: re-running the installer is idempotent" \
    "[ \"\$(wc -l < \"$NIRI\")\" = \"$before\" ] && [ \"\$(grep -Fc 'Taurus mouse-wheel binds' \"$NIRI\")\" = 1 ]"
check "niri: existing user binds are preserved" \
    'grep -Fq "Mod+Return { spawn \"kitty\"; }" "$NIRI"'

mkdir -p "$HOME/.config/sway/configDir" "$HOME/.config/mango/config" "$HOME/.config/umbriel/config" "$HOME/.config/hypr/config"
printf 'bindsym $mod+Return exec kitty\n' > "$HOME/.config/sway/configDir/keybinds"
printf 'bind=SUPER,Return,spawn,kitty\n' > "$HOME/.config/mango/config/keybinds.conf"
printf '[keybinds]\n"Mod+Return" = "spawn kitty"\n' > "$HOME/.config/umbriel/config/keybinds.toml"
printf 'hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("kitty"))\n' > "$HOME/.config/hypr/config/keybinds.lua"

ensure_compositor_binds sway mango umbriel hyprland >/dev/null
check "sway: wheel binds are appended" \
    'grep -Fq "bindsym --whole-window \$mod+button5 workspace next" "$HOME/.config/sway/configDir/keybinds"'
check "mango: wheel binds are appended" \
    'grep -Fq "axisbind=SUPER,DOWN,viewtoright" "$HOME/.config/mango/config/keybinds.conf"'
check "umbriel: wheel binds are appended" \
    'grep -Fq "\"Mod+WheelUp\" = { action = \"workspace-previous\", cooldown_ms = 150 }" "$HOME/.config/umbriel/config/keybinds.toml"'
check "hyprland: wheel binds are appended" \
    'grep -Fq "mouse_down" "$HOME/.config/hypr/config/keybinds.lua"'

[ "$failures" -eq 0 ] || { echo "$failures test(s) failed" >&2; exit 1; }
echo "all compositor bind tests passed"
