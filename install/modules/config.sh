CONFIG_DIR="$HOME/.config/taurus"
CONFIG_FILE="$CONFIG_DIR/settings.json"

init_taurus_config() {
    local project_root="$1"
    local wallpaper_dir="$2"
    local install_state="$3"
    local is_reinstall="$4"
    local template_json="$project_root/config/taurus/settings.json"
    local script_path="$project_root/src/scripts/location.sh"

    if [[ "$install_state" == "current" && "$is_reinstall" != "true" ]]; then
        return 0
    fi

    mkdir -p "$CONFIG_DIR"

    local sys_lang="en"
    command -v detect_system_language &>/dev/null && sys_lang="$(detect_system_language)"

    if [ -f "$template_json" ]; then
        if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
            local merged_json
            merged_json=$(jq -s --arg wp "$wallpaper_dir" --arg lang "$sys_lang" '
                (.[0] * .[1])
                * (if ($wp | length > 0) then {wallpaperDir: $wp} else {} end)
                * (if (.[1].general.language // null) == null then {general: {language: $lang}} else {} end)
            ' "$template_json" "$CONFIG_FILE" 2>/dev/null)
            if [ -n "$merged_json" ]; then
                echo "$merged_json" > "$CONFIG_FILE"
            fi
        else
            local initial_json
            initial_json=$(jq --arg wp "$wallpaper_dir" --arg lang "$sys_lang" '
                . * (if ($wp | length > 0) then {wallpaperDir: $wp} else {} end)
                  * {general: {language: $lang}}
            ' "$template_json" 2>/dev/null)
            if [ -n "$initial_json" ]; then
                echo "$initial_json" > "$CONFIG_FILE"
            else
                cp "$template_json" "$CONFIG_FILE"
            fi
        fi
    elif [ ! -f "$CONFIG_FILE" ]; then
        if [ -n "$wallpaper_dir" ]; then
            echo "{\"wallpaperDir\": \"$wallpaper_dir\"}" > "$CONFIG_FILE"
        else
            echo "{}" > "$CONFIG_FILE"
        fi
    fi

    # Seed theme.colors from the selected static preset so that app theming
    # (bash prompt, GTK, Qt, kitty, ...) is generated on first boot instead of
    # waiting for the user to re-select the theme. Matugen themes generate their
    # own palette, so they are left alone.
    local _matugen
    _matugen=$(jq -r '.theme.matugen // false' "$CONFIG_FILE" 2>/dev/null)
    if [ "$_matugen" != "true" ]; then
        local _preset_name _preset_file _preset_colors _merged
        _preset_name=$(jq -r '.theme.activePreset // "Taurus"' "$CONFIG_FILE" 2>/dev/null)
        _preset_file="$project_root/src/assets/themes/${_preset_name}.json"
        if [ -f "$_preset_file" ]; then
            _preset_colors=$(jq '.colors' "$_preset_file" 2>/dev/null)
            if [ -n "$_preset_colors" ] && [ "$_preset_colors" != "null" ]; then
                _merged=$(jq --argjson colors "$_preset_colors" '.theme.colors = $colors' "$CONFIG_FILE" 2>/dev/null)
                if [ -n "$_merged" ]; then
                    echo "$_merged" > "$CONFIG_FILE"
                fi
            fi
        fi
    fi

    if [[ "$is_reinstall" == "true" || "$install_state" == "fresh" || "$install_state" == "legacy" ]]; then
        if [ -f "$script_path" ]; then
            bash "$script_path" --refresh >/dev/null 2>&1 || true
        elif [ -f "$HOME/.local/share/taurus/src/scripts/location.sh" ]; then
            bash "$HOME/.local/share/taurus/src/scripts/location.sh" --refresh >/dev/null 2>&1 || true
        fi
    fi
}
