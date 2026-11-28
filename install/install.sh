#!/usr/bin/env bash

set -e

setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

RAW_SLUG="${REPO_SLUG:-0x0ar/taurus}"
REPO_SLUG="$(printf '%s' "$RAW_SLUG" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_\/-]//g')"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/taurus-installer"
export REPO_SLUG
export TAURUS_INSTALLER=1

if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    PROJECT_ROOT="$(dirname "$INSTALL_DIR")"
else
    INSTALL_DIR=""
    PROJECT_ROOT=""
fi

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/install/modules/deps.sh" || ! -d "$PROJECT_ROOT/src" ]]; then
    if ! command -v git &>/dev/null; then
        if [ -n "${OS_RELEASE_FILE+x}" ]; then
            _os_release="$OS_RELEASE_FILE"
        elif [ -f /etc/os-release ]; then
            _os_release="/etc/os-release"
        elif [ -f /usr/lib/os-release ]; then
            _os_release="/usr/lib/os-release"
        else
            _os_release=""
        fi
        _os_id=""
        _os_like=""
        if [ -n "$_os_release" ] && [ -f "$_os_release" ]; then
            while IFS= read -r _line || [ -n "$_line" ]; do
                _line="${_line%$'\r'}"
                _line="${_line#"${_line%%[![:space:]]*}"}"
                case "$_line" in
                    ID=*|ID_LIKE=*)
                        _key="${_line%%=*}"
                        _val="${_line#*=}"
                        _val="${_val%"${_val##*[![:space:]]}"}"
                        if [ "${#_val}" -ge 2 ] && { { [ "${_val:0:1}" = '"' ] && [ "${_val: -1}" = '"' ]; } || { [ "${_val:0:1}" = "'" ] && [ "${_val: -1}" = "'" ]; }; }; then
                            _val="${_val:1:${#_val}-2}"
                        fi
                        if [ "$_key" = "ID" ]; then
                            _os_id="$_val"
                        else
                            _os_like="$_val"
                        fi
                        ;;
                esac
            done < "$_os_release"
        fi
        OS_IDS=" ${_os_id,,} ${_os_like,,} "
        if command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm --needed git
        fi
    fi
    if [ ! -d "$CACHE_BASE/.git" ]; then
        rm -rf "$CACHE_BASE"
        mkdir -p "$CACHE_BASE"
        git clone "https://github.com/${REPO_SLUG}.git" "$CACHE_BASE"
    else
        git -C "$CACHE_BASE" remote set-url origin "https://github.com/${REPO_SLUG}.git" 2>/dev/null || true
        git -C "$CACHE_BASE" fetch origin 2>/dev/null || true
        git -C "$CACHE_BASE" reset --hard origin/HEAD 2>/dev/null || git -C "$CACHE_BASE" reset --hard origin/main 2>/dev/null || git -C "$CACHE_BASE" reset --hard origin/master 2>/dev/null || true
    fi
    INSTALL_DIR="$CACHE_BASE/install"
    PROJECT_ROOT="$CACHE_BASE"
fi

export TAURUS_DIR="$PROJECT_ROOT/src"
export I18N_DIR="$PROJECT_ROOT/src/assets/languages"

MODULES_DIR="$INSTALL_DIR/modules"

source "$PROJECT_ROOT/src/scripts/i18n.sh"
source "$MODULES_DIR/os_release.sh"
source "$MODULES_DIR/pm.sh"
source "$MODULES_DIR/deps.sh"
source "$MODULES_DIR/ski.sh"
source "$MODULES_DIR/daemons.sh"
source "$MODULES_DIR/audio.sh"
source "$MODULES_DIR/gamma.sh"
source "$MODULES_DIR/core.sh"
source "$MODULES_DIR/state.sh"
source "$MODULES_DIR/migrate.sh"
source "$MODULES_DIR/deploy.sh"
source "$MODULES_DIR/compositor_binds.sh"
source "$MODULES_DIR/browser.sh"
source "$MODULES_DIR/version.sh"
source "$MODULES_DIR/config.sh"
source "$MODULES_DIR/service.sh"
source "$MODULES_DIR/bluetooth.sh"
source "$MODULES_DIR/extras.sh"
source "$MODULES_DIR/ui.sh"
source "$MODULES_DIR/uninstall.sh"

TELEMETRY_ID=$(get_telemetry_id)
ENABLE_TELEMETRY=$(get_telemetry_enabled)
OPT_SDDM=$(get_saved_preference OPT_SDDM "$OPT_SDDM")
OPT_BLUETOOTH=$(get_saved_preference OPT_BLUETOOTH "$OPT_BLUETOOTH")
SDDM_WAYLAND=$(get_saved_preference SDDM_WAYLAND "$SDDM_WAYLAND")
INSTALL_FULL_WALLPAPERS=$(get_saved_preference INSTALL_FULL_WALLPAPERS "$INSTALL_FULL_WALLPAPERS")
BROWSER=$(get_saved_browser)
export BROWSER
export BROWSER_PKG="$(browser_pkg "$BROWSER")"
export BROWSER_EXEC="$(browser_exec "$BROWSER")"
export BROWSER_DESKTOP="$(browser_desktop "$BROWSER")"

check_supported_os
bootstrap_installer_deps

INSTALL_STATE=$(detect_install_state)
OLD_VERSION=$(get_installed_version)
TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")
OLD_COMMIT=$(get_installed_commit)

init_compositor_detection
run_installer_ui

if [ "${TUI_HANDLED:-false}" = true ]; then
    exit 0
fi

if [ "$DO_UNINSTALL" = true ]; then
    uninstall_taurus "$PROJECT_ROOT"
    exit 0
fi

TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")

if [ "$ENABLE_TELEMETRY" = true ] && [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode init --version "$TARGET_VERSION" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY"
fi

if [[ "$INSTALL_STATE" == "legacy" ]]; then
    migrate_legacy "${SELECTED_COMPOSITORS[@]}"
elif [[ "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    backup_compositors "${SELECTED_COMPOSITORS[@]}"
fi

install_dependencies "$INSTALL_STATE" "$IS_REINSTALL" "${SELECTED_COMPOSITORS[@]}"
install_ski
install_audio_daemon
install_gamma_daemon
install_core_daemon

deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE" "${SELECTED_COMPOSITORS[@]}"
ensure_compositor_binds "${SELECTED_COMPOSITORS[@]}"
setup_default_browser
ensure_browser_binds "${SELECTED_COMPOSITORS[@]}"
setup_sddm "$PROJECT_ROOT" "$INSTALL_STATE" "$IS_REINSTALL"
setup_bluetooth
setup_extras
install_wallpapers "$INSTALL_FULL_WALLPAPERS"

WALLPAPER_DIR=$(get_wallpaper_dir)
init_taurus_config "$PROJECT_ROOT" "$WALLPAPER_DIR" "$INSTALL_STATE" "$IS_REINSTALL"

# Seed a random downloaded wallpaper (not the bundled fallback) as the current
# desktop wallpaper on fresh installs. The first launch reuses this exact file so
# the same background is restored on every login.
WALLPAPER_CACHE="$HOME/.cache/taurus/wallpaper"
mkdir -p "$WALLPAPER_CACHE"
if [[ "$IS_REINSTALL" != true ]] || [[ ! -f "$WALLPAPER_CACHE/current_wallpaper.png" ]]; then
    SEED_WALLPAPER=""
    if [ -d "$WALLPAPER_DIR" ]; then
        SEED_WALLPAPER="$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) ! -iname 'taurus-default.png' 2>/dev/null | shuf -n 1)"
    fi
    if [ -z "$SEED_WALLPAPER" ] && [ -f "$PROJECT_ROOT/src/assets/wallpapers/taurus-default.png" ]; then
        SEED_WALLPAPER="$PROJECT_ROOT/src/assets/wallpapers/taurus-default.png"
    fi
    if [ -n "$SEED_WALLPAPER" ]; then
        cp -f "$SEED_WALLPAPER" "$WALLPAPER_CACHE/current_wallpaper.png" 2>/dev/null || true
        basename "$SEED_WALLPAPER" > "$WALLPAPER_CACHE/current_default_name" 2>/dev/null || true
        printf '%s\n' "$SEED_WALLPAPER" > "$WALLPAPER_CACHE/installed_wallpaper_path" 2>/dev/null || true
    fi
fi

# Make the login screen show the same wallpaper as the desktop from the first boot,
# before Matugen has generated a palette and copied it there itself.
if [ "$OPT_SDDM" = true ] && [ -f "$WALLPAPER_CACHE/current_wallpaper.png" ]; then
    sudo install -d -m 755 /var/lib/taurus/sddm 2>/dev/null || true
    sudo cp -f "$WALLPAPER_CACHE/current_wallpaper.png" /var/lib/taurus/sddm/wallpaper 2>/dev/null || true
    sudo chmod 644 /var/lib/taurus/sddm/wallpaper 2>/dev/null || true
    if [ -f /var/lib/taurus/sddm/theme.conf ] && ! grep -q '^wallpaper=' /var/lib/taurus/sddm/theme.conf 2>/dev/null; then
        printf '\nwallpaper=/var/lib/taurus/sddm/wallpaper\n' | sudo tee -a /var/lib/taurus/sddm/theme.conf >/dev/null 2>&1 || true
    fi
fi
configure_ski_defaults

setup_services
hand_over_from_easyeffects
write_version_state "$TARGET_VERSION" "$TARGET_COMMIT" "$TELEMETRY_ID" "$ENABLE_TELEMETRY" "${SELECTED_COMPOSITORS[*]}" "$OPT_SDDM" "$SDDM_WAYLAND" "$INSTALL_FULL_WALLPAPERS" "$OPT_BLUETOOTH" "$BROWSER"

if [[ "$INSTALL_STATE" == "legacy" || "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    rm -f "$HOME/.local/state/taurus/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
fi

if [ "$ENABLE_TELEMETRY" = true ] && [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode done --version "$TARGET_VERSION" --old-version "$OLD_VERSION" --install-state "$INSTALL_STATE" --compositor "${SELECTED_COMPOSITORS[*]}" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY" --failed "${FAILED_PKGS[*]}"
fi

draw_completion_screen "$TARGET_VERSION" "$TARGET_COMMIT"
