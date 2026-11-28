#!/usr/bin/env bash

# Taurus targets Arch Linux only.
PM_MODULES_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/pm"

if ! command -v pacman &>/dev/null; then
    echo "Taurus supports Arch Linux (pacman) only." >&2
    exit 1
fi

PM_NAME="pacman"

PM_EXTRA_PKGS=()
PM_SDDM_EXTRA_PKGS=()
PM_SDDM_WAYLAND_DEFAULT=true
PM_SDDM_CURSOR_FIX=false
PM_AUDIO_BUILD_PKGS=()

source "$PM_MODULES_DIR/$PM_NAME.sh"
