#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
TAURUS_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/caching.sh" 2>/dev/null || true
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true

STATE_DIR="${QS_STATE_DIR:-$HOME/.local/state/taurus}"
FLAG_FILE="$STATE_DIR/first_launch.done"

check_status() {
    mkdir -p "$STATE_DIR"
    if [ -f "$FLAG_FILE" ]; then
        echo "SKIP"
        exit 0
    fi

    touch "$FLAG_FILE"

    WP_DIR=""
    if type get_setting >/dev/null 2>&1; then
        WP_DIR="$(get_setting "wallpaperDir" "")"
        [ -z "$WP_DIR" ] && WP_DIR="$(get_setting "wallpaper_dir" "")"
    fi

    # Reuse the wallpaper picked at install time so the desktop keeps the same
    # background that SDDM is already showing, and restores it on every login.
    SEED_FILE="${QS_CACHE_DIR:-$HOME/.cache/taurus}/wallpaper/installed_wallpaper_path"
    SEED_WP=""
    if [ -f "$SEED_FILE" ]; then
        SEED_WP="$(head -n 1 "$SEED_FILE" 2>/dev/null | tr -d '\r\n')"
    fi

    RANDOM_WP=""
    if [ -n "$SEED_WP" ] && [ -f "$SEED_WP" ]; then
        RANDOM_WP="$SEED_WP"
    elif [ -n "$WP_DIR" ] && [ -d "$WP_DIR" ]; then
        RANDOM_WP="$(find "$WP_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) 2>/dev/null | shuf -n 1)"
    fi

    START_QML=""
    if [ -f "$TAURUS_DIR/quickshell/serp/Start.qml" ]; then
        START_QML="$TAURUS_DIR/quickshell/serp/Start.qml"
    elif [ -f "$TAURUS_DIR/quickshell/Start.qml" ]; then
        START_QML="$TAURUS_DIR/quickshell/Start.qml"
    else
        START_QML="$(find "$TAURUS_DIR/quickshell" -type f -name "Start.qml" 2>/dev/null | head -n 1)"
    fi

    echo "FIRST|$RANDOM_WP|$START_QML"
}

open_guide() {
    local script_path="$TAURUS_DIR/scripts/qs_manager.sh"
    if [ -f "$script_path" ]; then
        bash "$script_path" open settings welcome
    fi
}

reset_state() {
    rm -f "$FLAG_FILE"
}

case "$1" in
    --check)
        check_status
        ;;
    --open-guide)
        open_guide
        ;;
    --reset)
        reset_state
        ;;
    *)
        exit 1
        ;;
esac
