#!/usr/bin/env bash
# Bluetooth is opt-in: bluez is already installed, the installer only enables its service.

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

cat > "$SANDBOX/sudo" <<EOF
#!/bin/sh
echo "\$*" >> "$SANDBOX/sudo.log"
EOF
chmod +x "$SANDBOX/sudo"
export PATH="$SANDBOX:$PATH"
t() { printf '%s' "$1"; }
detect_init_system() { echo systemd; }
# shellcheck disable=SC1090
source "$REPO_ROOT/install/modules/service.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/install/modules/bluetooth.sh"

OPT_BLUETOOTH=true
: > "$SANDBOX/sudo.log"
setup_bluetooth
check "bluetooth: enables and starts the service when opted in" \
    'grep -q "systemctl enable --now bluetooth.service" "$SANDBOX/sudo.log"'

OPT_BLUETOOTH=false
: > "$SANDBOX/sudo.log"
setup_bluetooth
check "bluetooth: leaves services untouched when opted out" \
    '[ ! -s "$SANDBOX/sudo.log" ]'

[ "$failures" -eq 0 ] || { echo "$failures test(s) failed" >&2; exit 1; }
echo "all bluetooth tests passed"
