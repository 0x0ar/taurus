#!/usr/bin/env bash
# The default browser choice must reach the package list, the XDG default and
# the Mod+F bind of every supported compositor, without clobbering other binds.
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
export PATH="$SANDBOX/bin:$PATH"
t() { printf '%s' "$1"; }

mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/xdg-settings" <<'EOF'
printf 'xdg-settings %s\n' "$*" >> "$XDG_LOG"
EOF
cat > "$SANDBOX/bin/xdg-mime" <<'EOF'
printf 'xdg-mime %s\n' "$*" >> "$XDG_LOG"
EOF
export XDG_LOG="$SANDBOX/xdg.log"
: > "$XDG_LOG"
chmod +x "$SANDBOX/bin/xdg-settings" "$SANDBOX/bin/xdg-mime"

# shellcheck disable=SC1090
source "$REPO_ROOT/install/modules/browser.sh"

check "firefox keeps its official package" '[ "$(browser_pkg firefox)" = "firefox" ]'
check "chromium keeps its official package" '[ "$(browser_pkg chromium)" = "chromium" ]'
check "brave uses the AUR package" '[ "$(browser_pkg brave)" = "brave-bin" ]'
check "zen uses the AUR package" '[ "$(browser_pkg zen)" = "zen-browser-bin" ]'
check "unknown ids fall back to firefox" '[ "$(browser_id somethingelse)" = "firefox" ]'
check "brave executable is brave-browser" '[ "$(browser_exec brave)" = "brave-browser" ]'

BROWSER=zen
setup_default_browser >/dev/null
check "xdg-settings sets the chosen desktop file" 'grep -Fq "xdg-settings set default-web-browser zen-browser.desktop" "$XDG_LOG"'
check "xdg-mime covers http, https and html" 'grep -Fq "xdg-mime default zen-browser.desktop x-scheme-handler/http x-scheme-handler/https text/html" "$XDG_LOG"'

mkdir -p "$HOME/.config/hypr/config" "$HOME/.config/niri/config" "$HOME/.config/sway/configDir" "$HOME/.config/mango/config" "$HOME/.config/umbriel/config"
cat > "$HOME/.config/hypr/config/keybinds.lua" <<'EOF'
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("kitty"))
EOF
cat > "$HOME/.config/niri/config/keybinds.kdl" <<'EOF'
binds {
    Mod+Return { spawn "kitty"; }
    Mod+F { spawn "firefox"; }
    Mod+Shift+F { toggle-window-floating; }
}
EOF
printf 'bindsym $mod+F exec firefox\nbindsym $mod+Return exec kitty\n' > "$HOME/.config/sway/configDir/keybinds"
printf 'bind=SUPER,F,spawn,firefox\nbind=SUPER,Return,spawn,kitty\n' > "$HOME/.config/mango/config/keybinds.conf"
printf '[keybinds]\n"Mod+F" = { action = "spawn firefox", repeat = false }\n"Mod+Return" = { action = "spawn kitty", repeat = false }\n' > "$HOME/.config/umbriel/config/keybinds.toml"

ensure_browser_binds hyprland niri sway mango umbriel >/dev/null

check "hyprland: Mod+F opens the chosen browser" \
    'grep -Fq "mainMod .. \" + F\", hl.dsp.exec_cmd(\"zen-browser\")" "$HOME/.config/hypr/config/keybinds.lua"'
check "hyprland: other F binds are untouched" \
    'grep -Fq "mainMod .. \" + SHIFT + F\", hl.dsp.window.float" "$HOME/.config/hypr/config/keybinds.lua"'
check "niri: Mod+F opens the chosen browser" \
    'grep -Fq "Mod+F { spawn \"zen-browser\"; }" "$HOME/.config/niri/config/keybinds.kdl"'
check "niri: binds block stays closed" \
    '[ "$(tail -n 1 "$HOME/.config/niri/config/keybinds.kdl")" = "}" ]'
check "sway: Mod+F opens the chosen browser" \
    'grep -Fq "bindsym \$mod+F exec zen-browser" "$HOME/.config/sway/configDir/keybinds"'
check "mango: Mod+F opens the chosen browser" \
    'grep -Fq "bind=SUPER,F,spawn,zen-browser" "$HOME/.config/mango/config/keybinds.conf"'
check "umbriel: Mod+F opens the chosen browser" \
    'grep -Fq "\"Mod+F\" = { action = \"spawn zen-browser\"" "$HOME/.config/umbriel/config/keybinds.toml"'
check "terminal bind survives in every compositor" \
    'grep -Rq "kitty" "$HOME/.config/hypr/config" "$HOME/.config/niri/config" "$HOME/.config/sway/configDir" "$HOME/.config/mango/config" "$HOME/.config/umbriel/config"'
check "a backup of the edited bind file is kept" \
    'ls "$HOME/.config/niri/config/keybinds.kdl".taurus-bak.* >/dev/null 2>&1'

before=$(sha256sum "$HOME/.config/niri/config/keybinds.kdl" | cut -d' ' -f1)
ensure_browser_binds niri >/dev/null
check "re-running with the same browser is idempotent" \
    "[ \"\$(sha256sum \"$HOME/.config/niri/config/keybinds.kdl\" | cut -d' ' -f1)\" = \"$before\" ]"

BROWSER=firefox
ensure_browser_binds niri >/dev/null
check "switching back restores firefox" \
    'grep -Fq "Mod+F { spawn \"firefox\"; }" "$HOME/.config/niri/config/keybinds.kdl"'

[ "$failures" -eq 0 ] || { echo "$failures test(s) failed" >&2; exit 1; }
echo "all browser tests passed"
