#!/usr/bin/env bash

declare -F qs_ensure_cache >/dev/null && return 0

if [ -z "${TAURUS_DIR:-}" ]; then
    SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    export TAURUS_DIR="$(dirname "$SCRIPT_DIR")"
fi

export QS_DIR="$TAURUS_DIR/quickshell"
export MAIN_QML="$QS_DIR/Shell.qml"
export IPC_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/taurus.sock"

export QS_CACHE_DIR="$HOME/.cache/taurus"
export QS_STATE_DIR="$HOME/.local/state/taurus"
export QS_RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/taurus"
export QS_LOG_DIR="$QS_RUN_DIR/logs"
export QS_SETTINGS="$HOME/.config/taurus/settings.json"

# taurus-core may be D-Bus-activated outside of taurusd and has no fallback for
# TAURUS_DIR (a name unique to Taurus), so the daemon hands just that to the bus.
# Only taurusd sets TAURUS_BUS_ENV=1: running the CLI (or an agent) from a checkout must
# never change the user's systemd environment.
_taurus_export_bus_env() {
    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment --systemd TAURUS_DIR 2>/dev/null || true
    fi
}
if [ "${TAURUS_BUS_ENV:-0}" = 1 ]; then _taurus_export_bus_env; fi

[[ -d "$QS_LOG_DIR" && -d "$QS_CACHE_DIR" && -d "$QS_STATE_DIR" ]] || mkdir -p "$QS_CACHE_DIR" "$QS_STATE_DIR" "$QS_RUN_DIR" "$QS_LOG_DIR"

qs_ensure_cache() {
    local WIDGET_NAME="$1"
    
    local WIDGET_UPPER="${WIDGET_NAME^^}"
    
    local WIDGET_CACHE="$QS_CACHE_DIR/$WIDGET_NAME"
    local WIDGET_STATE="$QS_STATE_DIR/$WIDGET_NAME"
    local WIDGET_RUN="$QS_RUN_DIR/$WIDGET_NAME"
    
    [[ -d "$WIDGET_RUN" && -d "$WIDGET_STATE" && -d "$WIDGET_CACHE" ]] || mkdir -p "$WIDGET_CACHE" "$WIDGET_STATE" "$WIDGET_RUN"
    
    export "QS_CACHE_${WIDGET_UPPER}=$WIDGET_CACHE"
    export "QS_STATE_${WIDGET_UPPER}=$WIDGET_STATE"
    export "QS_RUN_${WIDGET_UPPER}=$WIDGET_RUN"
}

if [ -d "$QS_DIR" ]; then
    for dir in "$QS_DIR"/*/; do
        [ -d "$dir" ] || continue
        
        dir_trimmed="${dir%/}"
        WIDGET_NAME="${dir_trimmed##*/}"
        
        qs_ensure_cache "$WIDGET_NAME"
    done
fi

qs_ensure_cache "focustime"

if [ -z "${TAURUS_INSTALLER:-}" ]; then
    ver=""
    if [ -f "$TAURUS_DIR/version.txt" ]; then
        read -r ver < "$TAURUS_DIR/version.txt" 2>/dev/null
    elif [ -f "$(dirname "$TAURUS_DIR")/version.txt" ]; then
        read -r ver < "$(dirname "$TAURUS_DIR")/version.txt" 2>/dev/null
    fi
    if [ ! -f "$QS_STATE_DIR/version" ]; then
        [ -z "$ver" ] && ver="${TAURUS_VERSION:-2.0.0}"
        echo "TAURUS_VERSION=\"$ver\"" > "$QS_STATE_DIR/version"
    elif [ -n "$ver" ] && ! grep -qxF "TAURUS_VERSION=\"$ver\"" "$QS_STATE_DIR/version"; then
        tmp="$QS_STATE_DIR/version.tmp.$$"
        if grep -q '^TAURUS_VERSION=' "$QS_STATE_DIR/version"; then
            sed "s|^TAURUS_VERSION=.*|TAURUS_VERSION=\"$ver\"|" "$QS_STATE_DIR/version" > "$tmp"
        else
            { echo "TAURUS_VERSION=\"$ver\""; cat "$QS_STATE_DIR/version"; } > "$tmp"
        fi
        mv -f "$tmp" "$QS_STATE_DIR/version"
    fi
fi

[ -f "$QS_STATE_DIR/quickactions/palettes.json" ] || echo "[]" > "$QS_STATE_DIR/quickactions/palettes.json"
