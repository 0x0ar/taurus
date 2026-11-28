#!/usr/bin/env bash
# Tests for the SDDM service handling in the installer. Sandbox only: sudo, distro hooks
# and filesystem writes are stubbed. The real display manager is never enabled or started.

set -u

REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
SANDBOX="$(mktemp -d)"
STUBS="$SANDBOX/stubs"
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

mkdir -p "$STUBS"
cat > "$STUBS/sudo" <<EOF
#!/bin/sh
echo "\$*" >> "$SANDBOX/sudo.log"
EOF
chmod +x "$STUBS/sudo"
export PATH="$STUBS:$PATH"
SUDO_LOG="$SANDBOX/sudo.log"

# shellcheck disable=SC1090
source "$REPO_ROOT/install/modules/service.sh"

: > "$SUDO_LOG"
enable_system_service_no_start sddm systemd
check "systemd: SDDM is enabled for boot, not started now" \
    '[ "$(cat "$SUDO_LOG")" = "systemctl enable sddm.service" ] && ! grep -qE -- "--now|start|-f" "$SUDO_LOG"'

: > "$SUDO_LOG"
enable_system_service_no_start sddm openrc
check "openrc: only added to the default runlevel" \
    '[ "$(cat "$SUDO_LOG")" = "rc-update add sddm default" ]'

: > "$SUDO_LOG"
enable_system_service_no_start sddm dinit
check "dinit: only enabled" '[ "$(cat "$SUDO_LOG")" = "dinitctl enable sddm" ]'

: > "$SUDO_LOG"
enable_system_service NetworkManager systemd
check "other services still start immediately" 'grep -q -- "--now NetworkManager.service" "$SUDO_LOG"'

: > "$SUDO_LOG"
enable_display_manager_only sddm systemd
check "display-manager helper enables without starting" \
    '[ "$(cat "$SUDO_LOG")" = "systemctl enable sddm.service" ]'

pm_enable_display_manager() { echo "$1 $2 hook" >> "$SUDO_LOG"; }
: > "$SUDO_LOG"
enable_display_manager_only sddm systemd
check "a distro display-manager hook is still used" '[ "$(cat "$SUDO_LOG")" = "sddm systemd hook" ]'
unset -f pm_enable_display_manager

# ---- the installer step itself ---------------------------------------------------------------
t() { echo "$1"; }
find_sddm_binary() { [ "$1" = weston ] && echo /usr/bin/weston; }
sddm_has_xorg() { return 1; }
OPT_SDDM=true
REPLACE_DM=false
SDDM_WAYLAND=true
PM_SDDM_CURSOR_FIX=false
# shellcheck disable=SC1090
source "$REPO_ROOT/install/modules/deploy.sh"

: > "$SUDO_LOG"
setup_sddm "$SANDBOX/project" fresh false
check "setup_sddm enables SDDM but never starts the greeter" \
    'grep -q "systemctl enable sddm.service" "$SUDO_LOG" && ! grep -qE -- "--now|systemctl (start|restart)|rc-service sddm start|dinitctl start" "$SUDO_LOG"'
check "setup_sddm still writes the greeter configuration" \
    'grep -q "tee /etc/sddm.conf.d/10-material-you.conf" "$SUDO_LOG"'
check "the installer links a shared, Matugen-writable theme.conf into SDDM" \
    'grep -q "ln -sfn \"\$sddm_colors_conf\" \"\$sddm_theme_dest/theme.conf\"" "$REPO_ROOT/install/modules/deploy.sh"'
check "the SDDM theme reads its colors from Matugen-provided config keys" \
    'grep -q "themedColor(\"primary\"" "$REPO_ROOT/config/sddm/themes/material-you/Main.qml" && grep -q "primaryDark=" "$REPO_ROOT/config/sddm/themes/material-you/theme.conf" && grep -q "{{colors.primary.dark.hex}}" "$REPO_ROOT/src/assets/matugen/apps/sddm/theme.conf"'
check "the SDDM theme uses the shared wallpaper seeded by the installer" \
    'grep -q "^wallpaper=/var/lib/taurus/sddm/wallpaper$" "$REPO_ROOT/config/sddm/themes/material-you/theme.conf"'

[ "$failures" -eq 0 ] || { echo "$failures test(s) failed" >&2; exit 1; }
echo "all sddm service tests passed"
