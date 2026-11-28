#!/usr/bin/env bash

# The bundled compositor configs are only copied on fresh installs/upgrades that
# replace the whole config. Keep that behaviour for user-customised files, but make
# sure the mouse-wheel binds added in 68290af reach existing configs on updates too.

_compositor_bind_file() {
    case "$1" in
        hyprland) printf '%s\n' "$HOME/.config/hypr/config/keybinds.lua" ;;
        niri)     printf '%s\n' "$HOME/.config/niri/config/keybinds.kdl" ;;
        sway)     printf '%s\n' "$HOME/.config/sway/configDir/keybinds" ;;
        mango)    printf '%s\n' "$HOME/.config/mango/config/keybinds.conf" ;;
        umbriel)  printf '%s\n' "$HOME/.config/umbriel/config/keybinds.toml" ;;
        *)        return 1 ;;
    esac
}

_compositor_bind_lines() {
    case "$1" in
        hyprland)
            printf '%s\n' \
                'hl.bind(mainMod .. " + mouse_down", hl.dsp.exec_cmd("hyprctl dispatch workspace e+1"))' \
                'hl.bind(mainMod .. " + mouse_up", hl.dsp.exec_cmd("hyprctl dispatch workspace e-1"))' \
                'hl.bind(mainMod .. " + mouse_right", hl.dsp.exec_cmd("hyprctl dispatch movefocus r"))' \
                'hl.bind(mainMod .. " + mouse_left", hl.dsp.exec_cmd("hyprctl dispatch movefocus l"))'
            ;;
        niri)
            printf '%s\n' \
                'Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }' \
                'Mod+WheelScrollUp cooldown-ms=150 { focus-workspace-up; }' \
                'Mod+WheelScrollRight cooldown-ms=150 { focus-column-right; }' \
                'Mod+WheelScrollLeft cooldown-ms=150 { focus-column-left; }'
            ;;
        sway)
            printf '%s\n' \
                'bindsym --whole-window $mod+button5 workspace next' \
                'bindsym --whole-window $mod+button4 workspace prev' \
                'bindsym --whole-window $mod+button7 focus right' \
                'bindsym --whole-window $mod+button6 focus left'
            ;;
        mango)
            printf '%s\n' \
                'axisbind=SUPER,DOWN,viewtoright' \
                'axisbind=SUPER,UP,viewtoleft' \
                'axisbind=SUPER,RIGHT,focusdir,right' \
                'axisbind=SUPER,LEFT,focusdir,left'
            ;;
        umbriel)
            printf '%s\n' \
                '"Mod+WheelDown" = { action = "workspace-next", cooldown_ms = 150 }' \
                '"Mod+WheelUp" = { action = "workspace-previous", cooldown_ms = 150 }' \
                '"Mod+WheelRight" = { action = "window-focus-right", cooldown_ms = 150 }' \
                '"Mod+WheelLeft" = { action = "window-focus-left", cooldown_ms = 150 }'
            ;;
        *) return 1 ;;
    esac
}

_ensure_compositor_binds_for() {
    local comp="$1"
    local file marker lines
    file="$(_compositor_bind_file "$comp")" || return 0
    [ -f "$file" ] || return 0

    lines="$(_compositor_bind_lines "$comp")" || return 0
    case "$comp" in
        niri)    marker='    // Taurus mouse-wheel binds (added by installer; safe to remove)' ;;
        hyprland) marker='-- Taurus mouse-wheel binds (added by installer; safe to remove)' ;;
        *)       marker='# Taurus mouse-wheel binds (added by installer; safe to remove)' ;;
    esac

    grep -Fq -- "$marker" "$file" && return 0

    local all_present=true line
    while IFS= read -r line; do
        grep -Fq -- "$line" "$file" || all_present=false
    done <<< "$lines"
    [ "$all_present" = true ] && return 0

    local block tmp
    block="$(printf '%s\n%s\n' "$marker" "$lines")"
    tmp="${file}.taurus-tmp.$$"

    if [ "$comp" = niri ]; then
        # keybinds.kdl wraps the binds in `binds { ... }`; insert before the closing brace.
        awk -v block="$block" '
            { line[NR] = $0 }
            END {
                close_at = 0
                for (i = NR; i >= 1; i--) if (line[i] ~ /^}/) { close_at = i; break }
                for (i = 1; i <= NR; i++) {
                    if (i == close_at) print block
                    print line[i]
                }
                if (close_at == 0) print block
            }
        ' "$file" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
    else
        { cat "$file"; printf '\n%s\n' "$block"; } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
    fi

    cp -p "$file" "${file}.taurus-bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    if mv -f "$tmp" "$file" 2>/dev/null; then
        echo "  $(t "installer.deploy.compositor_binds_added" "comp=$comp" 2>/dev/null || printf 'added mouse-wheel binds to %s' "$file")"
    else
        rm -f "$tmp"
    fi
}

ensure_compositor_binds() {
    local comp
    for comp in "$@"; do
        _ensure_compositor_binds_for "$comp" || true
    done
}
