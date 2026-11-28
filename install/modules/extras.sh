#!/usr/bin/env bash

# Optional extras, enabled with TAURUS_EXTRAS="tmux openrgb" (space separated).
#   tmux    - tmux with Omarchy-style bindings; Mod+Enter opens kitty + tmux
#   openrgb - OpenRGB and a boot service that turns all lighting off (backs the RGB tab of the settings window)

EXTRAS_CONFIG_DIR="${EXTRAS_CONFIG_DIR:-}"

_extras_root() {
    if command -v pkexec &>/dev/null; then pkexec "$@"; else sudo "$@"; fi
}

_extras_enabled() {
    case " ${TAURUS_EXTRAS:-} " in *" $1 "*) return 0 ;; esac
    return 1
}

_extras_src() {
    echo "${EXTRAS_CONFIG_DIR:-${PROJECT_ROOT:-.}/config/extras}"
}

setup_extra_tmux() {
    local src dest
    src="$(_extras_src)/tmux.conf"
    dest="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
    [ -f "$src" ] || return 0
    command -v tmux &>/dev/null || _extras_root pacman -S --needed --noconfirm tmux || return 0
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] && ! cmp -s "$src" "$dest" && cp -a "$dest" "$dest.taurus-backup"
    cp "$src" "$dest"
    # reload in a running server; tmux only reads its config on server start
    tmux source-file "$dest" 2>/dev/null || true
    echo "[ OK ] tmux configured: $dest"
}

setup_extra_openrgb() {
    command -v openrgb &>/dev/null || _extras_root pacman -S --needed --noconfirm openrgb || return 0

    # Device indexes differ per machine, so the unit detects them at boot and
    # sets each one to "Off" (falling back to Direct/black for devices without it).
    _extras_root tee /etc/systemd/system/rgb-off.service >/dev/null <<'UNIT'
[Unit]
Description=Keep all RGB lighting off
After=systemd-modules-load.service lm_sensors.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 5
ExecStart=/bin/bash -c 'n=$(/usr/bin/openrgb --list-devices | grep -c "^[0-9]*: "); for i in $(seq 0 $((n-1))); do /usr/bin/openrgb -d $i -m Off || /usr/bin/openrgb -d $i -m Direct -c 000000 -b 0; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    _extras_root systemctl daemon-reload
    _extras_root systemctl enable rgb-off.service
    echo "[ OK ] OpenRGB: rgb-off.service enabled"
}

setup_extras() {
    _extras_enabled tmux && setup_extra_tmux
    _extras_enabled openrgb && setup_extra_openrgb
    return 0
}
