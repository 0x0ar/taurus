#!/usr/bin/env bash
# cachyos-minimal.sh: a MINIMAL CachyOS install from the live ISO, as a base for Taurus.
#
# What it installs: the kernel (linux-cachyos), only the firmware, microcode and video driver
# your hardware needs, NetworkManager, sudo, git, curl, zram and btrfs tools. No editor, terminal,
# firewall service, Bluetooth, login manager, CachyOS "settings" or any other recommended extra.
# Taurus's own installer brings the rest (python, jq, base-devel, compositor, login screen...).
#
# !!! IT ERASES THE WHOLE DISK YOU CHOOSE. Other disks are never touched. !!!
#
# Run it from the CachyOS live ISO, as root, with network. In a terminal it opens a full-screen
# interface (arrow keys, Enter, Esc to go back); --plain asks the same questions as plain prompts.
#     sudo bash cachyos-minimal.sh --dry-run    # shows the whole plan, changes nothing
#     sudo bash cachyos-minimal.sh              # the real thing
#     bash cachyos-minimal.sh --print-packages  # the exact package list and download size
#
# UEFI only. btrfs only (subvolumes @ @home @log @cache), no disk encryption, systemd-boot.

set -Eeuo pipefail

VERSION="1.0"
TARGET="${ISO_TARGET:-/mnt}"
LOG="${ISO_LOG:-/tmp/taurus-iso-install.log}"

DRY_RUN=0
PRINT_PACKAGES=0
DISK=""
HOST_NAME=""
USER_NAME=""
LOCALE=""
TIMEZONE=""
KEYMAP=""
ESP_MIB=""
FIRMWARE_OVERRIDE=""
PACMAN_CONF="/etc/pacman.conf"
COPY_NETWORK=""
UI_MODE=""            # tui | plain | "" (auto: tui in a terminal)
PACKAGES=()
FIRMWARE=()
BTRFS_OPTS="noatime,compress=zstd:1,discard=async,space_cache=v2"

# ---- output ---------------------------------------------------------------------------------------

log() { printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }
info() { log "==> $*"; printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { log "warning: $*"; printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() { log "error: $*"; printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --dry-run              Show every command and file it would write; change nothing.
  --print-packages       Print the exact package list, count and download size, then exit.
  --disk /dev/DEVICE     Disk to ERASE (otherwise you are asked).
  --hostname NAME        Machine name (otherwise you are asked).
  --user NAME            Admin user, gets sudo (otherwise you are asked).
  --locale xx_XX.UTF-8   For example es_AR.UTF-8, es_ES.UTF-8, en_US.UTF-8.
  --timezone Area/City   For example UTC, America/Argentina/Buenos_Aires,
                         America/Argentina/Cordoba, America/Mexico_City, Europe/Madrid.
                         To see every valid zone: timedatectl list-timezones
  --keymap NAME          Console keyboard layout, for example us, la-latin1, es.
  --esp-size MiB         Size of the EFI partition (default 2048, from 512 to 8192).
  --firmware "a b"       Firmware packages to install instead of the detected ones ("none" for none).
  --pacman-conf FILE     pacman.conf to install with (default: the live ISO's /etc/pacman.conf).
  --copy-network yes|no  Copy this session's saved network connections to the new system.
  --plain                Plain prompts instead of the full-screen interface.
  --tui                  The full-screen interface even if it can't tell this is a terminal.
  -h, --help
EOF
}

# ---- running things (dry-run aware) -----------------------------------------------------------------

DRY() { [ "$DRY_RUN" -eq 1 ]; }

# shell-quote only the words that need it, so the printed commands stay readable
shq() {
    local w out=()
    for w in "$@"; do
        if [[ "$w" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then out+=("$w"); else out+=("$(printf '%q' "$w")"); fi
    done
    echo "${out[*]}"
}
# nothing is changed in either mode, so a machine that is not the ISO only gets warnings
relaxed() { [ "$DRY_RUN" -eq 1 ] || [ "$PRINT_PACKAGES" -eq 1 ]; }

run() {
    log "+ $(shq "$@")"
    printf '+ %s\n' "$(shq "$@")"
    DRY || "$@"
}

in_chroot() {
    log "+ arch-chroot $TARGET $(shq "$@")"
    printf '+ arch-chroot %s %s\n' "$TARGET" "$(shq "$@")"
    DRY || arch-chroot "$TARGET" "$@"
}

# like run / in_chroot, but the output is also appended to the log
run_logged() {
    log "+ $(shq "$@")"; printf '+ %s\n' "$(shq "$@")"
    DRY && return 0
    "$@" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
}
in_chroot_logged() {
    log "+ arch-chroot $TARGET $(shq "$@")"; printf '+ arch-chroot %s %s\n' "$TARGET" "$(shq "$@")"
    DRY && return 0
    arch-chroot "$TARGET" "$@" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
}

# put FILE [MODE]: write stdin to a file in the target
put() {
    local path="$1" mode="${2:-644}"
    if DRY; then
        printf '+ write %s\n' "$path"
        sed 's/^/      | /'
    else
        mkdir -p "$(dirname "$path")"
        cat > "$path"
        chmod "$mode" "$path"
    fi
}

# append FILE: add stdin to the end of a file in the target (created if missing)
append() {
    local path="$1"
    if DRY; then
        printf '+ append to %s\n' "$path"
        sed 's/^/      | /'
    else
        mkdir -p "$(dirname "$path")"
        cat >> "$path"
    fi
}

# ---- prompts ------------------------------------------------------------------------------------------

# ask VAR "Question" DEFAULT [validator]: skipped when VAR was given by a flag
ask() {
    local var="$1" question="$2" def="$3" valid="${4:-}" answer
    if [ -n "${!var}" ]; then
        if [ -n "$valid" ] && ! "$valid" "${!var}"; then die "invalid value for $var: ${!var}"; fi
        return 0
    fi
    while true; do
        read -r -p "$question [$def]: " answer || die "no input available"
        answer="${answer:-$def}"
        if [ -z "$valid" ] || "$valid" "$answer"; then
            printf -v "$var" '%s' "$answer"
            return 0
        fi
        warn "not valid, try again"
    done
}

valid_hostname() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]]; }
valid_user() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] && [ "$1" != root ]; }
valid_locale() {
    [[ "$1" =~ ^[a-z]{2,3}_[A-Z]{2}\.UTF-8$ ]] || return 1
    [ ! -r /usr/share/i18n/SUPPORTED ] || grep -qxF "$1 UTF-8" /usr/share/i18n/SUPPORTED
}
valid_timezone() { [[ "$1" =~ ^[A-Za-z0-9_+/-]+$ ]] && [ -f "/usr/share/zoneinfo/$1" ]; }
valid_keymap() {
    [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
    if command -v localectl >/dev/null 2>&1 && localectl list-keymaps >/dev/null 2>&1; then
        localectl list-keymaps | grep -qxF "$1"
    else
        return 0
    fi
}
valid_esp() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 512 ] && [ "$1" -le 8192 ]; }

# Print a few valid zoneinfo names, so you don't have to guess the Area/City format.
show_timezone_examples() {
    echo
    info "Common time zones (exact names, Area/City):"
    printf '  %-33s  %-33s  %s\n' \
        'UTC'                            'America/Argentina/Buenos_Aires' 'America/Argentina/Cordoba' \
        'America/Argentina/Mendoza'      'America/Argentina/Tucuman'     'America/Mexico_City' \
        'America/Bogota'                 'America/Lima'                  'America/Santiago' \
        'America/Sao_Paulo'              'America/New_York'              'Europe/Madrid' \
        'Europe/London'                  'Asia/Tokyo'                    'Australia/Sydney'
    printf '  All zones: %s\n' 'timedatectl list-timezones (press q to quit)'
    echo
}

# ---- hardware detection (overridable in tests) ---------------------------------------------------------------

lspci_nn() { lspci -nn "$@" 2>/dev/null || true; }

cpu_vendor() { awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo; }

ucode_package() {
    case "$(cpu_vendor)" in
        AuthenticAMD) echo amd-ucode ;;
        GenuineIntel) echo intel-ucode ;;
    esac
}

# vendor ids of PCI devices of the given class(es), one per line
pci_vendors() {
    local class
    for class in "$@"; do
        lspci_nn -d "::$class" | grep -o '\[[0-9a-f]\{4\}:[0-9a-f]\{4\}\]' | sed 's/^\[\(....\):.*/\1/'
    done | sort -u
}

gpu_vendors() { pci_vendors 0300 0302 0380; }
net_vendors() { pci_vendors 0200 0280; }
has_wifi() { [ -n "$(pci_vendors 0280)" ]; }

# Video driver packages for the GPUs found. Proprietary NVIDIA is NOT handled here.
video_packages() {
    local v out=()
    for v in $(gpu_vendors); do
        case "$v" in
            1002) out+=(mesa vulkan-radeon) ;;
            8086) out+=(mesa vulkan-intel) ;;
        esac
    done
    [ "${#out[@]}" -gt 0 ] || out=(mesa)
    printf '%s\n' "${out[@]}" | sort -u
}

has_nvidia() { gpu_vendors | grep -qx 10de; }

# Firmware packages for the GPUs and network cards found (linux-firmware is split by vendor).
firmware_packages() {
    local v
    {
        for v in $(gpu_vendors); do
            case "$v" in
                1002) echo linux-firmware-amdgpu ;;
                8086) echo linux-firmware-intel ;;
                10de) echo linux-firmware-nvidia ;;
            esac
        done
        for v in $(net_vendors); do
            case "$v" in
                10ec) echo linux-firmware-realtek ;;
                14c3) echo linux-firmware-mediatek ;;
                168c) echo linux-firmware-atheros ;;
                14e4) echo linux-firmware-broadcom ;;
                8086) echo linux-firmware-intel ;;
            esac
        done
    } | sort -u
}

# ---- package list ------------------------------------------------------------------------------------------------

# Mirror list packages for the CachyOS repos the pacman.conf actually uses.
mirrorlist_packages() {
    local conf="$1" f
    for f in $(sed -n 's|^Include[[:space:]]*=[[:space:]]*/etc/pacman.d/\(cachyos[a-z0-9-]*mirrorlist\)[[:space:]]*$|\1|p' "$conf" | sort -u); do
        echo "$f"
    done
}

build_package_list() {
    local ucode p
    PACKAGES=(base linux-cachyos mkinitcpio btrfs-progs dosfstools networkmanager sudo git curl zram-generator
              archlinux-keyring cachyos-keyring)
    ucode="$(ucode_package)"
    [ -z "$ucode" ] || PACKAGES+=("$ucode")
    while IFS= read -r p; do [ -z "$p" ] || PACKAGES+=("$p"); done < <(mirrorlist_packages "$PACMAN_CONF")
    while IFS= read -r p; do [ -z "$p" ] || PACKAGES+=("$p"); done < <(video_packages)
    for p in "${FIRMWARE[@]}"; do PACKAGES+=("$p"); done
    if has_wifi; then PACKAGES+=(wireless-regdb); fi
    mapfile -t PACKAGES < <(printf '%s\n' "${PACKAGES[@]}" | awk 'NF && !seen[$0]++')
}

# Everything pacstrap would download, resolved against a throw-away empty database. Fails early
# (before anything is erased) on a missing package or an unresolved dependency.
resolve_closure() {
    local tmp out status
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/db/local" "$tmp/cache" "$tmp/root"
    cp -r /var/lib/pacman/sync "$tmp/db/sync"
    cp /var/lib/pacman/local/ALPM_DB_VERSION "$tmp/db/local/ALPM_DB_VERSION" 2>/dev/null || echo 9 > "$tmp/db/local/ALPM_DB_VERSION"
    status=0
    out="$(pacman --config "$PACMAN_CONF" --dbpath "$tmp/db" --root "$tmp/root" --cachedir "$tmp/cache" --logfile /dev/null \
        -Sp --print-format '%n %v %s' "$@" 2>&1)" || status=$?
    rm -rf "$tmp"
    [ "$status" -eq 0 ] || { printf '%s\n' "$out" >&2; return 1; }
    printf '%s\n' "$out"
}

print_package_summary() {
    local closure="$1"
    printf '\nExplicit packages (%d):\n' "${#PACKAGES[@]}"
    printf '  %s\n' "${PACKAGES[@]}"
    printf '\nWith dependencies: %d packages, %s MiB to download\n' \
        "$(awk 'NF==3 && $3 ~ /^[0-9]+$/' <<< "$closure" | wc -l)" \
        "$(awk 'NF==3 && $3 ~ /^[0-9]+$/ {s += $3} END {printf "%.0f", s / 1048576}' <<< "$closure")"
}

# ---- disk -------------------------------------------------------------------------------------------------------------

part_path() { # part_path DISK N  (nvme0n1 -> nvme0n1p1, sda -> sda1)
    if [[ "$1" =~ [0-9]$ ]]; then echo "${1}p${2}"; else echo "${1}${2}"; fi
}

is_block_device() { [ -b "$1" ]; }
has_saved_connections() { compgen -G "/etc/NetworkManager/system-connections/*.nmconnection" >/dev/null; }

# The disk the live ISO itself booted from, if any.
live_medium_disk() {
    local src d pk
    for d in /run/archiso/bootmnt /run/miso/bootmnt /run/initramfs/live; do
        src="$(findmnt -no SOURCE "$d" 2>/dev/null || true)"
        [ -z "$src" ] && continue
        pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)"
        echo "/dev/${pk:-$(basename "$src")}"
        return 0
    done
}

candidate_disks() {
    lsblk -dnpo NAME,TYPE | awk '$2 == "disk" && $1 !~ /\/(zram|loop|ram|sr|fd)/ {print $1}'
}

show_disks() {
    lsblk -dpo NAME,SIZE,TYPE,TRAN,MODEL | awk 'NR == 1 || ($3 == "disk" && $1 !~ /\/(zram|loop|ram|sr|fd)/)'
}

# Partitions of the disk that are mounted or used as swap. If lsblk cannot tell, assume it is not safe.
mounted_on_disk() {
    local out
    if out="$(lsblk -nrpo NAME,MOUNTPOINTS "$1" 2>/dev/null)"; then :
    elif out="$(lsblk -nrpo NAME,MOUNTPOINT "$1" 2>/dev/null)"; then :
    else die "cannot read the mount state of $1 with lsblk"; fi
    awk 'NF > 1' <<< "$out" | sed 's/\\x0a/, /g'
}

check_disk() {
    local disk="$1" live mounts
    is_block_device "$disk" || die "$disk is not a block device"
    candidate_disks | grep -qx "$disk" || die "$disk is not a whole disk (give the disk, not a partition)"
    live="$(live_medium_disk)"
    [ -z "$live" ] || [ "$disk" != "$live" ] || die "$disk is the disk this live ISO booted from"
    mounts="$(mounted_on_disk "$disk")"
    if [ -n "$mounts" ]; then
        if DRY; then
            warn "something on $disk is mounted right now (a real run would refuse):"
        else
            printf '%s\n' "$mounts" >&2
            die "partitions of $disk are mounted or in use; unmount them first"
        fi
        printf '%s\n' "$mounts" >&2
    fi
}

sfdisk_script() { # sfdisk_script ESP_MIB
    cat <<EOF
label: gpt
size=${1}MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system"
type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name="CachyOS root"
EOF
}

# ---- generated files ---------------------------------------------------------------------------------------------------

fstab_fixup() {
    # no subvolid (a rollback would break it); the EFI partition must not be world readable
    sed -E -e 's/,subvolid=[0-9]+//' -e 's/subvolid=[0-9]+,//' -e 's/fmask=0022,dmask=0022/fmask=0077,dmask=0077/'
}

loader_entry() { # loader_entry ROOT_UUID
    cat <<EOF
title   CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=UUID=$1 rootflags=subvol=@ rw zswap.enabled=0
EOF
}

# ---- preflight -------------------------------------------------------------------------------------------------------------

preflight() {
    local tool
    for tool in lsblk findmnt sfdisk wipefs mkfs.fat mkfs.btrfs btrfs blkid mount umount pacstrap genfstab arch-chroot \
                partprobe udevadm pacman curl lspci; do
        command -v "$tool" >/dev/null 2>&1 || {
            if relaxed; then warn "missing on this system (needed on the ISO): $tool"; else die "missing tool: $tool"; fi
        }
    done
    if [ "$EUID" -ne 0 ] && ! relaxed; then die "run as root: sudo bash $0"; fi
    if [ ! -d /sys/firmware/efi ]; then
        if relaxed; then warn "this system is not booted in UEFI mode (a real run requires it)"; else die "not booted in UEFI mode: boot the ISO in UEFI"; fi
    fi
    if [ ! -d /run/archiso ] && [ ! -d /run/miso ]; then
        if relaxed; then warn "this does not look like a live ISO (a real run refuses)"; else die "this is not a live ISO. Refusing to run on an installed system"; fi
    fi
    if findmnt -rn "$TARGET" >/dev/null 2>&1 && ! relaxed; then
        die "$TARGET is already mounted; run: umount -R $TARGET"
    fi
    curl -fsS --max-time 10 -o /dev/null https://archlinux.org || {
        if relaxed; then warn "no network"; else die "no network (try: nmtui, or plug in a cable)"; fi
    }
}

# ---- TUI ---------------------------------------------------------------------------------------------------------------
# A full-screen interface in plain bash: the live ISO has no python, dialog, whiptail or gum. It only gathers the same
# answers as the prompts above and then runs the same functions, so both modes install exactly the same system.

TUI=0                 # 1 = full-screen interface (chosen in main)
TUI_REPLY=""
TUI_KEY=""
TUI_CHAR=""
TUI_PENDING=""        # a key read too early while telling Esc apart from an arrow key
TUI_OUT=""            # stdout/stderr of the work shown on the progress screen
TUI_RENDER_PID=""
TUI_PROG_TITLE=""
TUI_PROG_STEPS=()
TUI_STEP=""           # "3/9" shown in the header
CLOSURE=""

T_RESET=$'\e[0m'; T_BOLD=$'\e[1m'; T_DIM=$'\e[2m'; T_REV=$'\e[7m'
T_ACC=$'\e[38;5;141m'; T_RED=$'\e[38;5;203m'; T_GREEN=$'\e[38;5;114m'; T_YELLOW=$'\e[38;5;221m'

tui_size() { # sets TUI_ROWS TUI_COLS
    local s=""
    s="$(stty size 2>/dev/null < /dev/tty)" || s=""
    TUI_ROWS="${s% *}"; TUI_COLS="${s#* }"
    [[ "$TUI_ROWS" =~ ^[0-9]+$ ]] && [ "$TUI_ROWS" -ge 10 ] || TUI_ROWS=24
    [[ "$TUI_COLS" =~ ^[0-9]+$ ]] && [ "$TUI_COLS" -ge 40 ] || TUI_COLS=80
}

tui_start() {
    exec 3>&1
    TUI=1
    TUI_OUT="${LOG}.screen"
    stty -echo 2>/dev/null < /dev/tty || true
    printf '\e[?1049h\e[?25l' >&3
}

tui_stop() {
    [ "$TUI" -eq 1 ] || return 0
    tui_progress_stop
    printf '\e[0m\e[?25h\e[?1049l' >&3
    stty echo 2>/dev/null < /dev/tty || true
    TUI=0
}

tui_at() { printf '\e[%d;%dH%s' "$1" "$2" "$3" >&3; } # tui_at ROW COL TEXT

# header, body text (lines) and the key hints at the bottom; returns the first free row in TUI_ROW
tui_frame() { # tui_frame TITLE TEXT HINTS
    local title="$1" text="$2" hints="$3" line row=4 w
    tui_size; w=$((TUI_COLS - 4))
    printf '\e[0m\e[2J\e[H' >&3
    tui_at 1 1 "${T_REV}${T_ACC}$(printf ' %-*s' $((TUI_COLS - 1)) "Taurus · CachyOS minimal install${TUI_STEP:+   ·   step $TUI_STEP}$( DRY && echo '   ·   DRY RUN')")${T_RESET}"
    tui_at 3 3 "${T_BOLD}${title}${T_RESET}"
    if [ -n "$text" ]; then
        while IFS= read -r line; do
            row=$((row + 1)); tui_at "$row" 3 "${line:0:$w}"
        done < <(printf '%s\n' "$text" | fold -s -w "$w")
    fi
    tui_at "$TUI_ROWS" 1 "${T_DIM}$(printf ' %-*s' $((TUI_COLS - 1)) "$hints")${T_RESET}"
    TUI_ROW=$((row + 2))
}

tui_key() { # sets TUI_KEY (UP DOWN LEFT RIGHT ENTER ESC BS TAB CHAR EOF) and TUI_CHAR
    local k="" c1="" c2="" rest=""
    TUI_CHAR=""
    if [ -n "$TUI_PENDING" ]; then k="$TUI_PENDING"; TUI_PENDING=""
    elif ! IFS= read -rsN1 k; then TUI_KEY=EOF; return 0; fi
    case "$k" in
        $'\e')
            IFS= read -rsN1 -t 0.05 c1 || true
            if [ "$c1" != "[" ] && [ "$c1" != "O" ]; then
                TUI_KEY=ESC; TUI_PENDING="$c1"; return 0
            fi
            IFS= read -rsN1 -t 0.05 c2 || true
            case "$c2" in
                A) TUI_KEY=UP ;; B) TUI_KEY=DOWN ;; C) TUI_KEY=RIGHT ;; D) TUI_KEY=LEFT ;;
                *) TUI_KEY=OTHER; IFS= read -rsN8 -t 0.01 rest || true ;;
            esac ;;
        $'\n'|$'\r') TUI_KEY=ENTER ;;
        $'\x7f'|$'\b') TUI_KEY=BS ;;
        $'\t') TUI_KEY=TAB ;;
        *) TUI_KEY=CHAR; TUI_CHAR="$k" ;;
    esac
}

# tui_menu TITLE TEXT DEFAULT ITEM...: an item starting with "!" is shown but can't be chosen.
# TUI_REPLY = chosen index, or -1 for Esc (back).
tui_menu() {
    local title="$1" text="$2" sel="$3"; shift 3
    local items=("$@") n=$# i top=0 avail label mark
    [ "$sel" -ge 0 ] && [ "$sel" -lt "$n" ] || sel=0
    while :; do
        tui_frame "$title" "$text" "↑/↓ move   Enter choose   Esc back"
        avail=$((TUI_ROWS - TUI_ROW - 2)); [ "$avail" -ge 3 ] || avail=3
        if [ "$sel" -lt "$top" ]; then top=$sel; fi
        if [ "$sel" -ge $((top + avail)) ]; then top=$((sel - avail + 1)); fi
        for ((i = top; i < n && i < top + avail; i++)); do
            label="${items[$i]}"; mark="  "
            if [ "${label:0:1}" = "!" ]; then
                label="${T_DIM}${label:1}${T_RESET}"
            elif [ "$i" -eq "$sel" ]; then
                label="${T_REV}${T_ACC} ${label:0:$((TUI_COLS - 10))} ${T_RESET}"; mark="${T_ACC}❯${T_RESET} "
            else
                label=" ${label:0:$((TUI_COLS - 10))}"
            fi
            tui_at $((TUI_ROW + i - top)) 3 "${mark}${label}"
        done
        if [ "$top" -gt 0 ]; then tui_at $((TUI_ROW - 1)) 5 "${T_DIM}↑ more${T_RESET}"; fi
        if [ $((top + avail)) -lt "$n" ]; then tui_at $((TUI_ROW + avail)) 5 "${T_DIM}↓ more${T_RESET}"; fi
        tui_key
        case "$TUI_KEY" in
            CHAR) case "$TUI_CHAR" in k) TUI_KEY=UP ;; j) TUI_KEY=DOWN ;; q) TUI_KEY=ESC ;; esac ;;
        esac
        case "$TUI_KEY" in
            UP) i=$sel; while [ "$i" -gt 0 ]; do i=$((i - 1)); [ "${items[$i]:0:1}" = "!" ] || { sel=$i; break; }; done ;;
            DOWN|TAB) i=$sel; while [ "$i" -lt $((n - 1)) ]; do i=$((i + 1)); [ "${items[$i]:0:1}" = "!" ] || { sel=$i; break; }; done ;;
            ENTER) if [ "${items[$sel]:0:1}" != "!" ]; then TUI_REPLY=$sel; return 0; fi ;;
            ESC|LEFT) TUI_REPLY=-1; return 0 ;;
            EOF) die "no input available" ;;
        esac
    done
}

# tui_input TITLE TEXT DEFAULT VALIDATOR HINT: TUI_REPLY = the value, or the function returns 1 on Esc (back)
tui_input() {
    local title="$1" text="$2" value="$3" valid="$4" hint="$5" error=""
    while :; do
        tui_frame "$title" "$text" "type   Backspace delete   Enter accept   Esc back"
        tui_at "$TUI_ROW" 3 "${T_ACC}❯${T_RESET} ${T_BOLD}${value}${T_RESET}${T_REV} ${T_RESET}"
        if [ -n "$error" ]; then tui_at $((TUI_ROW + 2)) 3 "${T_RED}${error}${T_RESET}"; fi
        if [ -n "$hint" ]; then tui_at $((TUI_ROW + 3)) 3 "${T_DIM}${hint}${T_RESET}"; fi
        tui_key
        case "$TUI_KEY" in
            CHAR) value+="$TUI_CHAR"; error="" ;;
            BS) value="${value%?}"; error="" ;;
            ENTER) if [ -z "$valid" ] || "$valid" "$value"; then TUI_REPLY="$value"; return 0; fi
                   error="\"$value\" is not valid." ;;
            ESC) return 1 ;;
            EOF) die "no input available" ;;
        esac
    done
}

# tui_pick TITLE TEXT CURRENT VALIDATOR HINT CHOICE...: a list with "Other…" at the end for typing a value
tui_pick() {
    local title="$1" text="$2" cur="$3" valid="$4" hint="$5"; shift 5
    local choices=("$@") i def=-1
    for i in "${!choices[@]}"; do [ "${choices[$i]}" != "$cur" ] || def=$i; done
    if [ "$def" -lt 0 ] && [ -n "$cur" ]; then choices=("$cur" "${choices[@]}"); def=0; fi
    [ "$def" -ge 0 ] || def=0
    while :; do
        tui_menu "$title" "$text" "$def" "${choices[@]}" "Other…"
        [ "$TUI_REPLY" -ge 0 ] || return 1
        if [ "$TUI_REPLY" -lt "${#choices[@]}" ]; then
            if [ -z "$valid" ] || "$valid" "${choices[$TUI_REPLY]}"; then TUI_REPLY="${choices[$TUI_REPLY]}"; return 0; fi
            def=$TUI_REPLY; continue
        fi
        if tui_input "$title" "$text" "" "$valid" "$hint"; then return 0; fi
    done
}

tui_welcome() {
    TUI_STEP=""
    tui_menu "Welcome" "This installs a MINIMAL CachyOS as a base for Taurus: kernel, the firmware your hardware needs, NetworkManager, sudo, git and oh-my-bash. Taurus's own installer brings the rest after the first boot.

It ERASES THE WHOLE DISK YOU CHOOSE. Other disks are never touched. Nothing is changed until you confirm at the end.

UEFI only · btrfs (@ @home @log @cache) · systemd-boot · no disk encryption" 0 \
        "Start" "Quit without changing anything"
    if [ "$TUI_REPLY" -ne 0 ]; then tui_stop; echo "Nothing was changed."; exit 0; fi
}

# one screen per answer; Esc goes back one screen. Values already set (flags, or a previous round) are the defaults.
tui_gather() {
    local step=1 total=9 live disks=() labels=() d size model why mounts i def fw nvidia_note ans
    while [ "$step" -le "$total" ]; do
        TUI_STEP="$step/$total"
        case "$step" in
        1)  live="$(live_medium_disk)"; disks=(); labels=(); def=0
            while IFS= read -r d; do
                [ -n "$d" ] || continue
                size="$(lsblk -dno SIZE "$d" 2>/dev/null | tr -d ' ')"; model="$(lsblk -dno MODEL "$d" 2>/dev/null | sed 's/ *$//')"
                why=""
                if [ -n "$live" ] && [ "$d" = "$live" ]; then why="the live ISO booted from it"
                else mounts="$(mounted_on_disk "$d" 2>/dev/null || true)"; if [ -n "$mounts" ] && ! DRY; then why="something on it is mounted"; fi
                fi
                [ "$d" != "$DISK" ] || def=${#disks[@]}
                disks+=("$d")
                if [ -n "$why" ]; then labels+=("!$(printf '%-16s %8s  %s  (not available: %s)' "$d" "$size" "$model" "$why")")
                else labels+=("$(printf '%-16s %8s  %s' "$d" "$size" "$model")"); fi
            done < <(candidate_disks)
            [ "${#disks[@]}" -gt 0 ] || die "no disks found"
            tui_menu "Disk to ERASE" "Only the disk you choose is erased. Everything on it is lost." "$def" "${labels[@]}"
            if [ "$TUI_REPLY" -lt 0 ]; then tui_welcome; continue; fi
            DISK="${disks[$TUI_REPLY]}"; check_disk "$DISK" ;;
        2)  tui_input "Hostname" "The name of this machine on the network." "${HOST_NAME:-cachyos}" valid_hostname \
                "Letters, numbers and dashes, up to 63, not starting with a dash." || { step=$((step - 1)); continue; }
            HOST_NAME="$TUI_REPLY" ;;
        3)  tui_input "User name" "Your account. It gets sudo; root stays locked. The password is asked during the install." \
                "$USER_NAME" valid_user "Lowercase letters, numbers, - and _, starting with a letter. Not root." \
                || { step=$((step - 1)); continue; }
            USER_NAME="$TUI_REPLY" ;;
        4)  tui_pick "Language (locale)" "Language and formats of the installed system." "${LOCALE:-$(tui_default_locale)}" valid_locale \
                "Format xx_XX.UTF-8, for example fr_FR.UTF-8." \
                en_US.UTF-8 es_AR.UTF-8 es_ES.UTF-8 es_MX.UTF-8 es_CL.UTF-8 es_CO.UTF-8 pt_BR.UTF-8 \
                || { step=$((step - 1)); continue; }
            LOCALE="$TUI_REPLY" ;;
        5)  tui_pick "Time zone" "Choose yours, or Other… to type any Area/City (every zone: timedatectl list-timezones)." \
                "${TIMEZONE:-$(tui_default_tz)}" valid_timezone "Area/City, exactly as in /usr/share/zoneinfo, for example Europe/Paris." \
                UTC America/Argentina/Buenos_Aires America/Argentina/Cordoba America/Argentina/Mendoza America/Argentina/Tucuman \
                America/Mexico_City America/Bogota America/Lima America/Santiago America/Sao_Paulo America/New_York \
                Europe/Madrid Europe/London Asia/Tokyo Australia/Sydney \
                || { step=$((step - 1)); continue; }
            TIMEZONE="$TUI_REPLY" ;;
        6)  tui_pick "Console keyboard" "Keyboard layout of the text console (the desktop has its own setting)." \
                "${KEYMAP:-$(tui_default_keymap)}" valid_keymap "A name from: localectl list-keymaps" \
                us la-latin1 es br-abnt2 de fr uk \
                || { step=$((step - 1)); continue; }
            KEYMAP="$TUI_REPLY" ;;
        7)  tui_input "EFI partition size" "Size in MiB of the FAT32 /boot partition (kernels live there). 2048 is plenty." \
                "${ESP_MIB:-2048}" valid_esp "A number from 512 to 8192." || { step=$((step - 1)); continue; }
            ESP_MIB="$TUI_REPLY" ;;
        8)  fw="$(firmware_packages | tr '\n' ' ' | sed 's/ *$//')"; nvidia_note=""
            if has_nvidia; then nvidia_note="

NVIDIA GPU found: the proprietary NVIDIA driver is NOT installed here (it is a later step). An AMD/Intel GPU, if any, works."; fi
            tui_menu "Firmware" "Detected for this hardware: ${fw:-none}${nvidia_note}" 0 \
                "Use the detected firmware" "No firmware" "Type my own list"
            case "$TUI_REPLY" in
                -1) step=$((step - 1)); continue ;;
                0) FIRMWARE_OVERRIDE="${fw:-none}" ;;
                1) FIRMWARE_OVERRIDE=none ;;
                2) tui_input "Firmware" "Packages separated by spaces, all named linux-firmware-*." "$fw" tui_valid_firmware \
                       "For example: linux-firmware-amdgpu linux-firmware-realtek" || continue
                   FIRMWARE_OVERRIDE="${TUI_REPLY:-none}" ;;
            esac ;;
        9)  if has_saved_connections; then
                tui_menu "Network" "Copy the network connections saved in this live session (Wi-Fi passwords included) to the new system?" \
                    "$([ "$COPY_NETWORK" = no ] && echo 1 || echo 0)" "Yes, copy them" "No"
                case "$TUI_REPLY" in -1) step=$((step - 1)); continue ;; 0) COPY_NETWORK=yes ;; 1) COPY_NETWORK=no ;; esac
            else
                COPY_NETWORK=no
            fi ;;
        esac
        step=$((step + 1))
    done
    TUI_STEP=""
}

tui_default_locale() { local l="${LANG:-en_US.UTF-8}"; valid_locale "$l" || l=en_US.UTF-8; echo "$l"; }
tui_default_tz() { local t; t="$(timedatectl show -p Timezone --value 2>/dev/null || true)"; valid_timezone "${t:-x}" || t=UTC; echo "$t"; }
tui_default_keymap() { local k; k="$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null | head -n1)"; valid_keymap "${k:-x}" || k=us; echo "$k"; }
tui_valid_firmware() { local p; for p in $1; do [[ "$p" =~ ^linux-firmware[a-z0-9-]*$ ]] || return 1; done; }

# ---- progress screen: a background loop redraws the steps and the last lines of the output ----

tui_progress_draw() {
    local title="$1"; shift
    local steps=("$@") frame=0 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' cur i row lines w mark avail seen
    set +e
    while :; do
        tui_size; w=$((TUI_COLS - 6))
        seen="$(sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$TUI_OUT" 2>/dev/null | grep -a '^==> ' | sed 's/^==> //')"
        cur=-1
        for i in "${!steps[@]}"; do
            if grep -qF -- "${steps[$i]}" <<< "$seen"; then cur=$i; fi
        done
        tui_frame "$title" "" "working… the output is also saved in $LOG"
        row=$TUI_ROW
        for i in "${!steps[@]}"; do
            if [ "$i" -lt "$cur" ]; then mark="${T_GREEN}✓${T_RESET}"
            elif [ "$i" -eq "$cur" ]; then mark="${T_ACC}${spin:$((frame % 10)):1}${T_RESET}"
            else mark="${T_DIM}·${T_RESET}"; fi
            tui_at "$row" 3 "$mark $( [ "$i" -eq "$cur" ] && printf '%s' "$T_BOLD")${steps[$i]}${T_RESET}"
            row=$((row + 1))
        done
        row=$((row + 1))
        tui_at "$row" 3 "${T_DIM}── output ──${T_RESET}"; row=$((row + 1))
        avail=$((TUI_ROWS - row - 1))
        if [ "$avail" -gt 0 ]; then
            tr '\r' '\n' < "$TUI_OUT" 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -av '^[[:space:]]*$' | tail -n "$avail" \
            | while IFS= read -r lines; do tui_at "$row" 3 "${T_DIM}${lines:0:$w}${T_RESET}"; row=$((row + 1)); done
        fi
        frame=$((frame + 1))
        sleep 0.2
    done
}

tui_progress_start() { # tui_progress_start TITLE STEP...
    TUI_PROG_TITLE="$1"; shift; TUI_PROG_STEPS=("$@")
    tui_progress_draw "$TUI_PROG_TITLE" "${TUI_PROG_STEPS[@]}" &
    TUI_RENDER_PID=$!
}

tui_progress_stop() {
    if [ -n "$TUI_RENDER_PID" ]; then
        kill "$TUI_RENDER_PID" 2>/dev/null || true
        wait "$TUI_RENDER_PID" 2>/dev/null || true
        TUI_RENDER_PID=""
    fi
}

# tui_work TITLE "STEP|STEP|..." FUNCTION...: runs the functions in this shell (so they can set variables and die)
# with their output going to the progress screen
tui_work() {
    local title="$1" steps="$2" f; shift 2
    local list=(); IFS='|' read -r -a list <<< "$steps"
    : > "$TUI_OUT"
    tui_progress_start "$title" "${list[@]}"
    for f in "$@"; do "$f" >> "$TUI_OUT" 2>&1 < /dev/null; done
    tui_progress_stop
}

# passwd needs the real terminal: pause the progress screen for it
tui_password() {
    local tries=0
    tui_progress_stop
    printf '\e[0m\e[?25h\e[?1049l' >&3; stty echo 2>/dev/null < /dev/tty || true
    printf '\n\e[1mPassword for %s\e[0m (asked twice; nothing is shown while you type)\n' "$USER_NAME" >&3
    local tty=/dev/tty
    { : < /dev/tty; } 2>/dev/null || tty=/dev/stdin
    until arch-chroot "$TARGET" passwd "$USER_NAME" < "$tty" >&3 2>&3; do
        tries=$((tries + 1))
        [ "$tries" -lt 3 ] || die "could not set a password for $USER_NAME"
    done
    stty -echo 2>/dev/null < /dev/tty || true
    printf '\e[?1049h\e[?25l' >&3
    tui_progress_start "$TUI_PROG_TITLE" "${TUI_PROG_STEPS[@]}"
}

tui_summary() { # TUI_REPLY: 0 install, 1 change something, 2 quit
    local plan pk
    plan="$(summary | sed '1,2d')"
    pk="$(grep -a '^With dependencies' "$TUI_OUT" | tail -n1)"
    tui_menu "Ready to install" "$plan
  Packages       ${pk#With dependencies: }" 0 \
        "$( DRY && echo "Run the dry run (shows the commands, changes nothing)" || echo "Install now: ERASE $DISK")" \
        "Change something" "Quit without changing anything"
    [ "$TUI_REPLY" -ge 0 ] || TUI_REPLY=1
}

tui_confirm() {
    local phrase="ERASE $DISK"
    DRY && return 0
    tui_input "Last check" "THIS ERASES EVERYTHING ON $DISK.

$(lsblk -f "$DISK" 2>/dev/null)

To continue, type exactly:  $phrase" "" "" "Esc goes back without changing anything." || return 1
    [ "$TUI_REPLY" = "$phrase" ]
}

tui_main() {
    tui_start
    tui_welcome
    local ready=0
    while [ "$ready" -eq 0 ]; do
        tui_gather
        tui_work "Preparing" "Checking that every package resolves" prepare_packages
        while :; do
            tui_summary
            case "$TUI_REPLY" in
                0) if tui_confirm; then ready=1; break; fi ;;   # a wrong confirmation shows the plan again
                1) break ;;
                2) tui_stop; echo "Nothing was changed."; exit 0 ;;
            esac
        done
    done
    STAGE="install"
    tui_work "Installing on $DISK" "Partitioning|Formatting|Creating the btrfs subvolumes|Installing the packages|Configuring|Shell: oh-my-bash|Users|Initramfs and bootloader|Checks passed" \
        install_system verify_install
    tui_stop
    finish
}

# ---- main --------------------------------------------------------------------------------------------------------------------

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --print-packages) PRINT_PACKAGES=1 ;;
            --disk) DISK="${2:?--disk needs a value}"; shift ;;
            --hostname) HOST_NAME="${2:?}"; shift ;;
            --user) USER_NAME="${2:?}"; shift ;;
            --locale) LOCALE="${2:?}"; shift ;;
            --timezone) TIMEZONE="${2:?}"; shift ;;
            --keymap) KEYMAP="${2:?}"; shift ;;
            --esp-size) ESP_MIB="${2:?}"; shift ;;
            --firmware) FIRMWARE_OVERRIDE="${2:?}"; shift ;;
            --pacman-conf) PACMAN_CONF="${2:?}"; shift ;;
            --copy-network) COPY_NETWORK="${2:?}"; shift ;;
            --plain) UI_MODE=plain ;;
            --tui) UI_MODE=tui ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
        shift
    done
}

choose_disk() {
    if [ -z "$DISK" ]; then
        echo
        info "Disks on this machine (only the one you choose is erased):"
        show_disks
        echo
        read -r -p "Disk to ERASE, for example /dev/nvme0n1: " DISK || die "no input available"
    fi
    check_disk "$DISK"
}

gather_config() {
    local def_locale def_tz def_keymap
    def_locale="${LANG:-en_US.UTF-8}"
    valid_locale "$def_locale" || def_locale="en_US.UTF-8"
    def_tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    valid_timezone "${def_tz:-x}" || def_tz="UTC"
    def_keymap="$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null | head -n1)"
    valid_keymap "${def_keymap:-x}" || def_keymap="us"
    ask HOST_NAME "Hostname" "cachyos" valid_hostname
    ask USER_NAME "User name (gets sudo; root is locked)" "" valid_user
    ask LOCALE "Locale" "$def_locale" valid_locale
    [ -n "$TIMEZONE" ] || show_timezone_examples
    ask TIMEZONE "Time zone (examples above, or Area/City)" "$def_tz" valid_timezone
    ask KEYMAP "Console keyboard layout" "$def_keymap" valid_keymap
    ask ESP_MIB "EFI partition size in MiB" "2048" valid_esp
}

detect_firmware() {
    local fw answer
    if [ -n "$FIRMWARE_OVERRIDE" ]; then
        fw="$FIRMWARE_OVERRIDE"
    else
        fw="$(firmware_packages | tr '\n' ' ')"
        if has_nvidia; then
            warn "NVIDIA GPU found. This script does not install the proprietary NVIDIA driver (the open"
            warn "kernel module package for linux-cachyos is a later step). The AMD/Intel GPU, if any, works."
        fi
        if [ -t 0 ] && [ "$PRINT_PACKAGES" -eq 0 ]; then
            echo
            info "Firmware for the hardware found: ${fw:-none detected}"
            read -r -p "Press Enter to accept, type your own list (space separated), or 'none': " answer || answer=""
            [ -z "$answer" ] || fw="$answer"
        fi
    fi
    [ "$fw" != none ] || fw=""
    FIRMWARE=()
    local p
    for p in $fw; do
        [[ "$p" =~ ^linux-firmware[a-z0-9-]*$ ]] || die "not a firmware package: $p"
        FIRMWARE+=("$p")
    done
}

confirm_erase() {
    local phrase="ERASE $DISK" answer
    DRY && return 0
    echo
    printf '\033[31m%s\033[0m\n' "THIS ERASES EVERYTHING ON $DISK"
    lsblk -f "$DISK" || true
    echo
    read -r -p "To continue type exactly '$phrase': " answer || die "no input available"
    [ "$answer" = "$phrase" ] || die "not confirmed; nothing was changed"
}

summary() {
    echo
    info "Plan"
    printf '  Disk           %s (ERASED)\n' "$DISK"
    printf '  Layout         EFI %s MiB (FAT32, /boot) + btrfs, no encryption\n' "$ESP_MIB"
    printf '  Subvolumes     @ @home @log @cache\n'
    printf '  Bootloader     systemd-boot, kernel linux-cachyos\n'
    printf '  Host / user    %s / %s (sudo; root locked)\n' "$HOST_NAME" "$USER_NAME"
    printf '  Locale / tz    %s / %s, keymap %s\n' "$LOCALE" "$TIMEZONE" "$KEYMAP"
    printf '  Repositories   %s\n' "$(grep -E '^\[[a-z0-9-]+\]' "$PACMAN_CONF" | grep -v '^\[options\]' | tr -d '[]' | tr '\n' ' ')"
    printf '  Not touched    %s\n' "$(candidate_disks | grep -vx "$DISK" | tr '\n' ' ')"
}

install_system() {
    local esp root root_uuid
    esp="$(part_path "$DISK" 1)"
    root="$(part_path "$DISK" 2)"

    info "Partitioning $DISK"
    run wipefs -af "$DISK"
    if DRY; then
        printf '+ sfdisk %s <<EOF\n' "$DISK"; sfdisk_script "$ESP_MIB"; echo EOF
    else
        sfdisk_script "$ESP_MIB" | sfdisk --wipe always --wipe-partitions always "$DISK"
    fi
    run udevadm settle
    run partprobe "$DISK"
    run udevadm settle

    info "Formatting"
    run mkfs.fat -F 32 -n ESP "$esp"
    run mkfs.btrfs -f -L CachyOS "$root"

    info "Creating the btrfs subvolumes and mounting"
    run mkdir -p "$TARGET"
    run mount "$root" "$TARGET"
    local sv
    for sv in @ @home @log @cache; do run btrfs subvolume create "$TARGET/$sv"; done
    run umount "$TARGET"
    run mount -o "$BTRFS_OPTS,subvol=@" "$root" "$TARGET"
    run mkdir -p "$TARGET/boot" "$TARGET/home" "$TARGET/var/log" "$TARGET/var/cache"
    run mount -o "$BTRFS_OPTS,subvol=@home" "$root" "$TARGET/home"
    run mount -o "$BTRFS_OPTS,subvol=@log" "$root" "$TARGET/var/log"
    run mount -o "$BTRFS_OPTS,subvol=@cache" "$root" "$TARGET/var/cache"
    run mount -o fmask=0077,dmask=0077 "$esp" "$TARGET/boot"

    info "Installing the packages (this downloads the system)"
    run_logged pacstrap -C "$PACMAN_CONF" "$TARGET" "${PACKAGES[@]}"

    info "Configuring"
    if DRY; then printf '+ genfstab -U %s | fixups > %s/etc/fstab\n' "$TARGET" "$TARGET"
    else genfstab -U "$TARGET" | fstab_fixup > "$TARGET/etc/fstab"; fi
    run cp "$PACMAN_CONF" "$TARGET/etc/pacman.conf"
    local ml
    for ml in /etc/pacman.d/mirrorlist /etc/pacman.d/cachyos*mirrorlist; do
        [ -e "$ml" ] || continue
        run cp "$ml" "$TARGET/etc/pacman.d/$(basename "$ml")"
    done
    in_chroot pacman-key --populate archlinux cachyos

    printf '%s\n' "$HOST_NAME" | put "$TARGET/etc/hostname"
    put "$TARGET/etc/hosts" <<EOF
127.0.0.1  localhost
::1        localhost
127.0.1.1  $HOST_NAME
EOF
    run ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$TARGET/etc/localtime"
    in_chroot hwclock --systohc || warn "could not set the hardware clock (not fatal)"
    if DRY; then printf '+ enable %s in %s/etc/locale.gen\n' "$LOCALE" "$TARGET"
    else sed -i "s/^#\\(${LOCALE//./\\.} UTF-8\\)/\\1/" "$TARGET/etc/locale.gen"; fi
    DRY || grep -q "^${LOCALE//./\\.} UTF-8" "$TARGET/etc/locale.gen" || die "locale $LOCALE is not in locale.gen"
    in_chroot locale-gen
    printf 'LANG=%s\n' "$LOCALE" | put "$TARGET/etc/locale.conf"
    printf 'KEYMAP=%s\n' "$KEYMAP" | put "$TARGET/etc/vconsole.conf"
    put "$TARGET/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
    put "$TARGET/etc/sudoers.d/10-wheel" 440 <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
    in_chroot visudo -cf /etc/sudoers.d/10-wheel

    if [ "$COPY_NETWORK" != no ] && has_saved_connections; then
        if [ -z "$COPY_NETWORK" ] && [ -t 0 ]; then
            read -r -p "Copy the network connections (Wi-Fi passwords) saved in this live session to the new system? [Y/n] " COPY_NETWORK || true
        fi
        case "${COPY_NETWORK:-yes}" in
            n|N|no|NO) ;;
            *) run mkdir -p "$TARGET/etc/NetworkManager/system-connections"
               run cp -a /etc/NetworkManager/system-connections/. "$TARGET/etc/NetworkManager/system-connections/" ;;
        esac
    fi

    info "Shell: oh-my-bash"
    install_oh_my_bash

    info "Users"
    in_chroot useradd -m -G wheel -s /bin/bash "$USER_NAME"
    in_chroot passwd -l root
    set_password

    info "Initramfs and bootloader"
    in_chroot_logged mkinitcpio -P
    in_chroot_logged bootctl install --esp-path=/boot
    root_uuid="<root-uuid>"
    DRY || root_uuid="$(blkid -s UUID -o value "$root")"
    loader_entry "$root_uuid" | put "$TARGET/boot/loader/entries/cachyos.conf"
    put "$TARGET/boot/loader/loader.conf" <<'EOF'
default  cachyos.conf
timeout  3
editor   no
EOF
    in_chroot systemctl enable NetworkManager.service systemd-timesyncd.service systemd-boot-update.service
}

# oh-my-bash lives in /opt (shared, read-only for users; update it with: pkexec git -C /opt/oh-my-bash pull)
# and /etc/skel/.bashrc loads it, so the user created next starts with it. It sets no prompt of its own:
# Taurus themes the prompt (app theme "Bash"). Not fatal: without it bash works as usual.
OMB_REPO="https://github.com/ohmybash/oh-my-bash.git"
install_oh_my_bash() {
    if ! in_chroot_logged git clone --depth 1 "$OMB_REPO" /opt/oh-my-bash; then
        warn "could not download oh-my-bash (not fatal): the shell works without it"
        return 0
    fi
    append "$TARGET/etc/skel/.bashrc" <<'EOF'

# --- oh-my-bash (installed in /opt by the Taurus ISO installer) ---
export OSH='/opt/oh-my-bash'
OSH_THEME=""                                 # no theme: Taurus sets the prompt (app theme "Bash")
OSH_CACHE_DIR="$HOME/.cache/oh-my-bash"      # /opt is read-only for users
DISABLE_AUTO_UPDATE=true                     # update with: pkexec git -C /opt/oh-my-bash pull
completions=(git ssh)
aliases=(general)
plugins=(git bashmarks)
[[ -f $OSH/oh-my-bash.sh ]] && source "$OSH/oh-my-bash.sh"
EOF
}

set_password() {
    local tries=0
    DRY && { printf '+ arch-chroot %s passwd %s   (asks for the password)\n' "$TARGET" "$USER_NAME"; return 0; }
    if [ "$TUI" -eq 1 ]; then tui_password; return 0; fi
    until arch-chroot "$TARGET" passwd "$USER_NAME"; do
        tries=$((tries + 1))
        [ "$tries" -lt 3 ] || die "could not set a password for $USER_NAME"
    done
}

verify_install() {
    DRY && return 0
    local f
    for f in boot/vmlinuz-linux-cachyos boot/initramfs-linux-cachyos.img boot/loader/entries/cachyos.conf \
             boot/EFI/BOOT/BOOTX64.EFI boot/EFI/systemd/systemd-bootx64.efi etc/fstab etc/hostname; do
        [ -s "$TARGET/$f" ] || die "check failed: $TARGET/$f is missing. Do NOT reboot; see $LOG"
    done
    awk '$2 == "/" && $4 ~ /(^|,)subvol=\/@(,|$)/ {ok = 1} END {exit !ok}' "$TARGET/etc/fstab" \
        || die "check failed: root is not on the @ subvolume in fstab"
    grep -q '[[:space:]]/boot[[:space:]]' "$TARGET/etc/fstab" || die "check failed: /boot is not in fstab"
    info "Checks passed: kernel, initramfs, bootloader, fstab"
}

finish() {
    DRY && { echo; info "Dry run finished: nothing was changed."; return 0; }
    cp "$LOG" "$TARGET/var/log/taurus-iso-install.log" 2>/dev/null || true
    run sync
    run umount -R "$TARGET"
    cat <<EOF

$(printf '\033[32m%s\033[0m' "Done.")  Remove the ISO and reboot.

If you ever need a rescue shell: root is locked, so boot this ISO again and use arch-chroot.

Then, logged in as $USER_NAME on the text console:
  1. Network: Ethernet works as is. Wi-Fi:  nmtui
  2. Install Taurus (it installs its own dependencies, the compositor and the login screen):
       curl -fsSL https://0x0ar.github.io/taurus/install.sh | bash
  3. Bluetooth is not enabled. If you use it, after Taurus:  sudo systemctl enable --now bluetooth

The log of this install is saved in /var/log/taurus-iso-install.log
EOF
}

# STAGE is "install" only once something has been changed; a failure before that changes nothing.
STAGE="checks"
LAST_FAILED=""

on_exit() {
    local rc=$?
    if [ "$TUI" -eq 1 ]; then
        tui_stop
        if [ "$rc" -ne 0 ] && [ -s "$TUI_OUT" ]; then
            printf '\033[2mLast output:\033[0m\n' >&2; tail -n 15 "$TUI_OUT" >&2
        fi
    fi
    [ "$rc" -ne 0 ] || return 0
    if [ "$STAGE" = install ]; then
        printf '\033[31merror:\033[0m the install stopped (exit %s) at: %s\n' "$rc" "${LAST_FAILED:-unknown}" >&2
        printf 'Nothing is unmounted, so you can inspect %s. The log is %s.\n' "$TARGET" "$LOG" >&2
        printf 'Do NOT reboot into a half-installed system.\n' >&2
    fi
}

# the full-screen interface needs a terminal on both ends
use_tui() {
    case "$UI_MODE" in
        tui) return 0 ;;
        plain) return 1 ;;
    esac
    [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]
}

prepare_packages() {
    detect_firmware
    # the live ISO's package databases can be old; refreshing them only affects the live system
    if ! relaxed; then run pacman -Sy --noconfirm --needed archlinux-keyring cachyos-keyring; fi
    build_package_list
    info "Checking that every package resolves (before anything is erased)"
    CLOSURE="$(resolve_closure "${PACKAGES[@]}")" || die "the package list does not resolve; nothing was changed"
    print_package_summary "$CLOSURE"
}

main() {
    parse_args "$@"
    trap 'LAST_FAILED="$BASH_COMMAND (line $LINENO)"' ERR
    trap on_exit EXIT
    : > "$LOG" 2>/dev/null || true
    info "cachyos-minimal $VERSION$( DRY && echo ' (dry run: nothing will be changed)')"
    preflight
    if [ "$PRINT_PACKAGES" -eq 0 ] && use_tui; then
        tui_main
        return 0
    fi
    if [ "$PRINT_PACKAGES" -eq 0 ]; then
        choose_disk
        gather_config
    fi
    prepare_packages
    if [ "$PRINT_PACKAGES" -eq 1 ]; then exit 0; fi
    summary
    confirm_erase
    STAGE="install"
    install_system
    verify_install
    finish
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
