#!/usr/bin/env bash

# Default browser selection shared by the interactive TUI and the plain installer.
# The TUI passes BROWSER/BROWSER_PKG/BROWSER_EXEC/BROWSER_DESKTOP as environment
# variables; the plain installer derives them from the saved preference.

if ! declare -f _compositor_bind_file >/dev/null; then
    source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/compositor_binds.sh"
fi

browser_supported() {
    case "${1:-}" in
        firefox|chromium|brave|zen) return 0 ;;
        *) return 1 ;;
    esac
}

browser_id() {
    if browser_supported "${1:-}"; then
        printf '%s\n' "$1"
    else
        printf '%s\n' "firefox"
    fi
}

browser_pkg() {
    case "$(browser_id "$1")" in
        chromium) printf '%s\n' "chromium" ;;
        brave)    printf '%s\n' "brave-bin" ;;
        zen)      printf '%s\n' "zen-browser-bin" ;;
        *)        printf '%s\n' "firefox" ;;
    esac
}

browser_exec() {
    case "$(browser_id "$1")" in
        chromium) printf '%s\n' "chromium" ;;
        brave)    printf '%s\n' "brave-browser" ;;
        zen)      printf '%s\n' "zen-browser" ;;
        *)        printf '%s\n' "firefox" ;;
    esac
}

browser_desktop() {
    case "$(browser_id "$1")" in
        chromium) printf '%s\n' "chromium.desktop" ;;
        brave)    printf '%s\n' "brave-browser.desktop" ;;
        zen)      printf '%s\n' "zen-browser.desktop" ;;
        *)        printf '%s\n' "firefox.desktop" ;;
    esac
}

setup_default_browser() {
    local id desktop
    id="$(browser_id "${BROWSER:-firefox}")"
    desktop="$(browser_desktop "$id")"

    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-web-browser "$desktop" >/dev/null 2>&1 || true
    fi
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default "$desktop" x-scheme-handler/http x-scheme-handler/https text/html >/dev/null 2>&1 || true
    fi

    printf '[ OK ] %s\n' "$(t "installer.browser.default_ok" "browser=$id" 2>/dev/null || printf 'Default browser set to %s' "$id")"
}

_ensure_browser_bind_for() {
    local id="$1" comp="$2" file exec tmp
    exec="$(browser_exec "$id")"
    file="$(_compositor_bind_file "$comp")" || return 0
    [ -f "$file" ] || return 0

    tmp="${file}.taurus-tmp.$$"
    case "$comp" in
        hyprland)
            sed '/mainMod \.\. " + F"/ s/exec_cmd("[^"]*")/exec_cmd("'"$exec"'")/' "$file" > "$tmp"
            ;;
        niri)
            sed '/^[[:space:]]*Mod+F[[:space:]]*{/ s/spawn "[^"]*"/spawn "'"$exec"'"/' "$file" > "$tmp"
            ;;
        sway)
            sed '/bindsym \$mod+F / s/exec .*/exec '"$exec"'/' "$file" > "$tmp"
            ;;
        mango)
            sed '/^bind=SUPER,F,/ s/,spawn,.*/,spawn,'"$exec"'/' "$file" > "$tmp"
            ;;
        umbriel)
            sed '/^"Mod+F"[[:space:]]*=/ s/"spawn [^"]*"/"spawn '"$exec"'"/' "$file" > "$tmp"
            ;;
        *)
            rm -f "$tmp"
            return 0
            ;;
    esac

    if cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
        return 0
    fi

    cp -p "$file" "${file}.taurus-bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    if mv -f "$tmp" "$file" 2>/dev/null; then
        printf '  %s\n' "$(t "installer.browser.bind_ok" "comp=$comp" "browser=$id" 2>/dev/null || printf 'Mod+F now opens %s in %s' "$exec" "$comp")"
    else
        rm -f "$tmp"
    fi
}

ensure_browser_binds() {
    local id; id="$(browser_id "${BROWSER:-firefox}")"
    local comp
    for comp in "$@"; do
        _ensure_browser_bind_for "$id" "$comp" || true
    done
}
