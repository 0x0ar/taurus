#!/usr/bin/env bash

declare -F qs_ensure_cache >/dev/null || source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

CONFIG_SETTINGS_JSON="${QS_SETTINGS:-$HOME/.config/taurus/settings.json}"

_config_ensure_settings() {
    local dir
    dir="$(dirname "$CONFIG_SETTINGS_JSON")"
    [[ -d "$dir" ]] || mkdir -p "$dir"
    [[ -s "$CONFIG_SETTINGS_JSON" ]] || echo '{}' > "$CONFIG_SETTINGS_JSON"
}

get_setting() {
    local key="$1"
    local fallback="${2:-}"
    _config_ensure_settings
    local val
    val="$(jq -r --arg k "$key" 'if has($k) then .[$k] else "__MISSING__" end' "$CONFIG_SETTINGS_JSON" 2>/dev/null)"
    if [[ "$val" == "__MISSING__" || "$val" == "null" ]]; then
        printf '%s' "$fallback"
    else
        printf '%s' "$val"
    fi
}

set_setting() {
    local key="$1"
    local value="$2"
    _config_ensure_settings

    local json_value
    if echo "$value" | jq -e . > /dev/null 2>&1; then
        json_value="$value"
    else
        json_value="$(jq -Rn --arg v "$value" '$v')"
    fi

    local tmp="${CONFIG_SETTINGS_JSON}.tmp"
    if jq --arg k "$key" --argjson v "$json_value" '. + {($k): $v}' "$CONFIG_SETTINGS_JSON" > "$tmp" 2>/dev/null; then
        if jq -e . "$tmp" > /dev/null 2>&1; then
            mv "$tmp" "$CONFIG_SETTINGS_JSON"
        fi
    fi
}

update_settings_bulk() {
    local json_obj="$1"
    _config_ensure_settings
    local tmp="${CONFIG_SETTINGS_JSON}.tmp"
    if jq --argjson patch "$json_obj" '. + $patch' "$CONFIG_SETTINGS_JSON" > "$tmp" 2>/dev/null; then
        if jq -e . "$tmp" > /dev/null 2>&1; then
            mv "$tmp" "$CONFIG_SETTINGS_JSON"
        fi
    fi
}

# ---- backups and shipped defaults (used by `taurus config`) ----

# The settings that ship with the install. Packages install config/ next to src/; the
# one-line installer copies only bin/ and src/, so a copy also lives in src/assets.
config_defaults_path() {
    local base="${TAURUS_DIR:-/usr/share/taurus/src}" sibling
    sibling="$(dirname "$base")/config/taurus/settings.json"
    if [ -f "$sibling" ]; then
        printf '%s' "$sibling"
    else
        printf '%s' "$base/assets/settings.default.json"
    fi
}

config_backup_dir() {
    printf '%s' "${QS_STATE_DIR:-$HOME/.local/state/taurus}/backups"
}

# Copy settings.json to <state>/backups/settings.<timestamp>.json and keep the newest 20.
config_backup() {
    [[ -s "$CONFIG_SETTINGS_JSON" ]] || return 0
    local dir stamp
    dir="$(config_backup_dir)"
    mkdir -p "$dir" || return 0
    stamp="$(date +%Y%m%d-%H%M%S)-$$"
    cp -- "$CONFIG_SETTINGS_JSON" "$dir/settings.$stamp.json" 2>/dev/null || return 0
    # shellcheck disable=SC2012
    ls -1t "$dir"/settings.*.json 2>/dev/null | tail -n +21 | while IFS= read -r old; do rm -f -- "$old"; done
}
