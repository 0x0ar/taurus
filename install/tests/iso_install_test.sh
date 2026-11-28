#!/usr/bin/env bash
# Tests for install/iso/cachyos-minimal.sh. No root, no real disk: every command that could change
# a system (sfdisk, mkfs, mount, pacstrap, arch-chroot, ...) is a stub that only records itself.
# What matters most is checked here: nothing outside the chosen disk is ever named, a wrong
# confirmation / a mounted disk / a partition / the live medium all stop BEFORE anything is erased.

set -u

REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
SCRIPT="$REPO_ROOT/install/iso/cachyos-minimal.sh"
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

check "the script has valid bash syntax" 'bash -n "$SCRIPT"'
check "--help works" 'bash "$SCRIPT" --help | grep -q "ERASES"'
check "--help shows time zone examples (Argentina included) and how to list them" \
    'bash "$SCRIPT" --help | grep -q "America/Argentina/Buenos_Aires" && bash "$SCRIPT" --help | grep -q "timedatectl list-timezones"'
check "an unknown option is rejected" '! bash "$SCRIPT" --nope >/dev/null 2>&1'

# ---- library functions ------------------------------------------------------------------------------
ISO_LOG="$SANDBOX/lib.log"; export ISO_LOG
# shellcheck disable=SC1090
source "$SCRIPT"
set +e +o pipefail     # the script turns strict mode on when sourced; the tests do their own checking

check "partition names: nvme, mmc, sata, loop" \
    '[ "$(part_path /dev/nvme0n1 2)" = /dev/nvme0n1p2 ] && [ "$(part_path /dev/mmcblk0 1)" = /dev/mmcblk0p1 ] && [ "$(part_path /dev/sda 1)" = /dev/sda1 ] && [ "$(part_path /dev/loop0 2)" = /dev/loop0p2 ]'

truncate -s 20G "$SANDBOX/disk.img"
sfdisk_script 2048 | sfdisk --wipe always "$SANDBOX/disk.img" >/dev/null 2>&1
layout="$(sfdisk -J "$SANDBOX/disk.img" 2>/dev/null)"
check "the partition table is GPT with an EFI partition of the asked size and a root partition" \
    'jq -e ".partitiontable.label == \"gpt\" and (.partitiontable.partitions | length == 2) and (.partitiontable.partitions[0].size == 4194304) and (.partitiontable.partitions[0].type == \"C12A7328-F81F-11D2-BA4B-00A0C93EC93B\") and (.partitiontable.partitions[1].type == \"4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709\")" <<< "$layout" >/dev/null'
check "the root partition takes the rest of the disk" \
    'jq -e "(.partitiontable.partitions[1].start == (.partitiontable.partitions[0].start + .partitiontable.partitions[0].size)) and ((.partitiontable.partitions[1].start + .partitiontable.partitions[1].size) >= (.partitiontable.lastlba - 2048))" <<< "$layout" >/dev/null'

# hardware fixtures: a class-aware fake of `lspci -nn -d ::CLASS`
FIXTURE="$SANDBOX/lspci"
lspci_nn() { # lspci_nn -d ::0300
    local class="${2#::}"
    grep "\[$class\]:" "$FIXTURE" || true
}
cat > "$FIXTURE" <<'EOF'
03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [1002:7551] (rev c0)
08:00.0 Network controller [0280]: MEDIATEK Corp. MT7922 802.11ax PCI Express Wireless Network Adapter [14c3:0616]
09:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
10:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Granite Ridge [Radeon 610M] [1002:13c0] (rev e6)
EOF
check "AMD GPU + MediaTek Wi-Fi + Realtek NIC: only those firmware packages" \
    '[ "$(firmware_packages | tr "\n" " ")" = "linux-firmware-amdgpu linux-firmware-mediatek linux-firmware-realtek " ]'
check "AMD GPU: mesa and vulkan-radeon, nothing else" '[ "$(video_packages | tr "\n" " ")" = "mesa vulkan-radeon " ]'
check "a Wi-Fi card is detected" 'has_wifi'
cat > "$FIXTURE" <<'EOF'
00:02.0 VGA compatible controller [0300]: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics] [8086:46a6]
00:14.3 Network controller [0280]: Intel Corporation Alder Lake-P PCH CNVi WiFi [8086:51f0]
EOF
check "Intel GPU and Wi-Fi: intel firmware and vulkan-intel" \
    '[ "$(firmware_packages | tr "\n" " ")" = "linux-firmware-intel " ] && [ "$(video_packages | tr "\n" " ")" = "mesa vulkan-intel " ]'
cat > "$FIXTURE" <<'EOF'
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [10de:2782]
00:02.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Raphael [1002:164e]
EOF
check "NVIDIA is flagged (not installed) and the AMD GPU still works" 'has_nvidia && [ "$(video_packages | tr "\n" " ")" = "mesa vulkan-radeon " ]'
: > "$FIXTURE"
check "no PCI devices (a VM): mesa only, no firmware, no Wi-Fi package" \
    '[ "$(video_packages | tr "\n" " ")" = "mesa " ] && [ -z "$(firmware_packages)" ] && ! has_wifi'

cpu_vendor() { echo AuthenticAMD; }
check "AMD CPU gets amd-ucode" '[ "$(ucode_package)" = amd-ucode ]'
cpu_vendor() { echo GenuineIntel; }
check "Intel CPU gets intel-ucode" '[ "$(ucode_package)" = intel-ucode ]'
cpu_vendor() { echo AuthenticAMD; }

printf '[options]\n[cachyos-znver4] \nInclude = /etc/pacman.d/cachyos-v4-mirrorlist \n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' > "$SANDBOX/pacman.conf"
check "mirror list packages follow the pacman.conf, even with trailing spaces" \
    '[ "$(mirrorlist_packages "$SANDBOX/pacman.conf" | tr "\n" " ")" = "cachyos-mirrorlist cachyos-v4-mirrorlist " ]'

PACMAN_CONF="$SANDBOX/pacman.conf"
FIRMWARE=(linux-firmware-amdgpu)
cat > "$FIXTURE" <<'EOF'
03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [1002:7551]
EOF
build_package_list
unwanted='nano|micro|vim|vi|neovim|alacritty|kitty|ufw|firewalld|bluez|bluez-utils|sddm|cachyos-settings|cachyos-hooks|fish|zsh|ananicy-cpp|scx-scheds|flatpak|snapper|openssh|wget|rsync|man-db|base-devel|yay|paru'
check "the explicit package list contains none of the extras you do not want" '! printf "%s\n" "${PACKAGES[@]}" | grep -qxE "$unwanted"'
check "the explicit package list has what is needed to boot and to start the Taurus installer" \
    'for p in base linux-cachyos mkinitcpio networkmanager sudo git curl btrfs-progs dosfstools amd-ucode; do printf "%s\n" "${PACKAGES[@]}" | grep -qx "$p" || exit 1; done'
check "no duplicate packages" '[ "$(printf "%s\n" "${PACKAGES[@]}" | sort | uniq -d | wc -l)" -eq 0 ]'

if [ -d /var/lib/pacman/sync ] && ls /var/lib/pacman/sync/*.db >/dev/null 2>&1 && grep -q '^\[core\]' /etc/pacman.conf; then
    PACMAN_CONF=/etc/pacman.conf
    closure="$(resolve_closure base linux-cachyos mkinitcpio networkmanager sudo git curl btrfs-progs dosfstools zram-generator mesa 2>&1)"
    check "the dependency closure resolves from the real repos" '[ "$(awk "NF==3 && \$3 ~ /^[0-9]+\$/" <<< "$closure" | wc -l)" -gt 100 ]'
    check "the closure pulls none of the unwanted packages" '! awk "NF==3 {print \$1}" <<< "$closure" | grep -qxE "$unwanted|ufw|firewalld"'
    check "a package that does not exist makes resolve_closure fail (before anything is erased)" '! resolve_closure base this-package-does-not-exist >/dev/null 2>&1'
else
    echo "skip  closure checks (no pacman sync databases on this machine)"
fi

check "validators: hostname" 'valid_hostname cachyos-pc && ! valid_hostname "bad name" && ! valid_hostname -x'
check "validators: user (root and weird names rejected)" 'valid_user arao && ! valid_user root && ! valid_user "A B" && ! valid_user "1abc"'
check "validators: locale and EFI size" 'valid_locale en_US.UTF-8 && ! valid_locale "en_US.utf8; rm -rf /" && valid_esp 2048 && ! valid_esp 100 && ! valid_esp abc'
check "validators: time zone must exist" 'valid_timezone UTC && ! valid_timezone Nope/Nowhere && ! valid_timezone "../../etc/passwd"'

genfstab_sample='UUID=AAAA-BBBB /boot vfat rw,relatime,fmask=0022,dmask=0022,codepage=437 0 2
UUID=1111 / btrfs rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/@ 0 0
UUID=1111 /home btrfs rw,noatime,subvolid=257,subvol=/@home 0 0'
fixed="$(fstab_fixup <<< "$genfstab_sample")"
check "fstab: subvolid is removed and the EFI partition is not world readable" \
    '! grep -q subvolid <<< "$fixed" && grep -q "fmask=0077,dmask=0077" <<< "$fixed" && grep -q "subvol=/@ 0 0" <<< "$fixed" && grep -q "subvol=/@home" <<< "$fixed"'
check "boot entry points at the root subvolume and the CachyOS kernel" \
    'loader_entry ABC | grep -q "options root=UUID=ABC rootflags=subvol=@ rw" && loader_entry ABC | grep -q "linux   /vmlinuz-linux-cachyos"'

# ---- whole flow with stubs ----------------------------------------------------------------------------
STUBS="$SANDBOX/stubs"; mkdir -p "$STUBS"
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
CMDLOG="$SANDBOX/commands"; export CMDLOG
for c in wipefs mkfs.fat mkfs.btrfs btrfs mount umount partprobe udevadm sync pacman; do
    stub "$c" 'echo "$(basename "$0") $*" >> "$CMDLOG"'
done
stub sfdisk 'echo "sfdisk $*" >> "$CMDLOG"; cat > "$CMDLOG.sfdisk"'
stub blkid 'echo FAKE-UUID-1234'
stub curl 'exit 0'
stub findmnt 'exit 1'
stub lsblk '
args="$*"
case "$args" in
  "-dnpo NAME,TYPE") printf "/dev/fake0 disk\n/dev/fake1 disk\n/dev/zram0 disk\n/dev/loop3 disk\n" ;;
  "-dpo NAME,SIZE,TYPE,TRAN,MODEL") printf "NAME SIZE TYPE TRAN MODEL\n/dev/fake0 1T disk nvme Fake\n/dev/fake1 2T disk sata Data\n" ;;
  "-nrpo NAME,MOUNTPOINTS /dev/fake0") if [ "${FAKE_MOUNTED:-0}" = 1 ]; then printf "/dev/fake0 \n/dev/fake0p1 /boot\n"; else printf "/dev/fake0\n/dev/fake0p1\n"; fi ;;
  "-no PKNAME "*) echo "${FAKE_LIVE_PK:-}" ;;
  "-f /dev/fake0") echo "fake0 listing" ;;
esac'
stub genfstab 'cat <<EOF
UUID=AAAA-BBBB /boot vfat rw,relatime,fmask=0022,dmask=0022 0 2
UUID=FAKE-UUID-1234 / btrfs rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/@ 0 0
UUID=FAKE-UUID-1234 /home btrfs rw,noatime,subvolid=257,subvol=/@home 0 0
EOF'
stub pacstrap '
echo "pacstrap $*" >> "$CMDLOG"
t="${@: -$(( $# )):1}"
for a in "$@"; do case "$a" in /*) [ -d "$a" ] && tgt="$a" ;; esac; done
mkdir -p "$ISO_TARGET/etc/pacman.d" "$ISO_TARGET/boot" "$ISO_TARGET/etc/systemd" "$ISO_TARGET/var/log"
printf "#en_US.UTF-8 UTF-8\n#es_AR.UTF-8 UTF-8\n#es_ES.UTF-8 UTF-8\n" > "$ISO_TARGET/etc/locale.gen"
echo kernel > "$ISO_TARGET/boot/vmlinuz-linux-cachyos"'
stub arch-chroot '
echo "arch-chroot $*" >> "$CMDLOG"
case "$2 $3" in
  "git clone") [ -z "${FAIL_GIT_CLONE:-}" ] || exit 1 ;;
  "mkinitcpio -P") echo initramfs > "$1/boot/initramfs-linux-cachyos.img" ;;
  "bootctl install") mkdir -p "$1/boot/EFI/BOOT" "$1/boot/EFI/systemd"; echo e > "$1/boot/EFI/BOOT/BOOTX64.EFI"; echo e > "$1/boot/EFI/systemd/systemd-bootx64.efi" ;;
esac
exit 0'

# an ISO-like environment: replace only the things that read the real machine
setup_run() { # setup_run NAME
    RUN="$SANDBOX/run-$1"; rm -rf "$RUN"; mkdir -p "$RUN/mnt"
    : > "$CMDLOG"; rm -f "$CMDLOG.sfdisk"
}
run_install() { # run_install STDIN ARGS...  (in a subshell so the script's exit does not end the tests)
    local input="$1"; shift
    (
        trap - EXIT
        export ISO_TARGET="$RUN/mnt" ISO_LOG="$RUN/log" PATH="$STUBS:$PATH"
        # shellcheck disable=SC1090
        source "$SCRIPT"
        set +e
        lspci_nn() { :; }
        preflight() { :; }
        is_block_device() { [[ "$1" == /dev/fake* || "$1" == /dev/zram* ]]; }
        resolve_closure() { printf 'base 1 1000\nlinux-cachyos 1 2000\n'; }
        cpu_vendor() { echo AuthenticAMD; }
        has_saved_connections() { [ -n "${FAKE_CONNECTIONS:-}" ]; }
        mkdir -p "$ISO_TARGET/etc"
        main "$@" <<< "$input"
    ) > "$RUN/out" 2>&1
}
ARGS=(--hostname testbox --user tester --locale es_AR.UTF-8 --timezone UTC --keymap us --esp-size 1024 --firmware none --copy-network no)
destructive='^(wipefs|sfdisk|mkfs|btrfs|mount|pacstrap|arch-chroot)'

setup_run ok
run_install "ERASE /dev/fake0" --disk /dev/fake0 "${ARGS[@]}"; rc=$?
check "the full flow runs to the end and says what to do next" '[ "$rc" -eq 0 ] && grep -q "Remove the ISO and reboot" "$RUN/out" && grep -q "install.sh | bash" "$RUN/out"'
check "only the chosen disk is ever named in any command" \
    '[ -z "$(grep -o "/dev/[A-Za-z0-9/_-]*" "$CMDLOG" | grep -vE "^/dev/fake0(p[12])?$" | sort -u)" ]'
check "the other disk is only listed as not touched, never in a command" '! grep -q "fake1" "$CMDLOG" && grep -q "Not touched.*fake1" "$RUN/out"'
check "the commands run in a safe order: wipe, partition, format, mount, install, bootloader, unmount" \
    'o="$(awk "/^wipefs/{w=NR} /^sfdisk/{s=NR} /^mkfs.fat/{f=NR} /^mkfs.btrfs/{b=NR} /^pacstrap/{p=NR} /bootctl install/{c=NR} /^umount -R/{u=NR} END{print (w<s && s<f && f<b && b<p && p<c && c<u) ? \"yes\" : \"no\"}" "$CMDLOG")"; [ "$o" = yes ]'
check "the partition table asked of sfdisk has the requested EFI size" 'grep -q "size=1024MiB" "$CMDLOG.sfdisk"'
check "pacstrap gets exactly the explicit list and nothing extra" \
    'grep "^pacstrap" "$CMDLOG" | grep -q "base linux-cachyos mkinitcpio" && ! grep "^pacstrap" "$CMDLOG" | grep -qE " (nano|micro|vim|ufw|bluez|sddm)( |$)"'
check "four btrfs subvolumes are created and mounted with zstd/noatime" \
    '[ "$(grep -c "^btrfs subvolume create" "$CMDLOG")" -eq 4 ] && grep -q "subvol=@home" "$CMDLOG" && grep -q "compress=zstd:1" "$CMDLOG"'
T="$RUN/mnt"
check "hostname, hosts, locale, console keymap and zram are written" \
    '[ "$(cat $T/etc/hostname)" = testbox ] && grep -q "127.0.1.1  testbox" $T/etc/hosts && grep -q "LANG=es_AR.UTF-8" $T/etc/locale.conf && grep -q "KEYMAP=us" $T/etc/vconsole.conf && grep -q "zram-size = ram / 2" $T/etc/systemd/zram-generator.conf'
check "only the chosen locale is enabled in locale.gen" 'grep -q "^es_AR.UTF-8 UTF-8" $T/etc/locale.gen && ! grep -q "^es_ES" $T/etc/locale.gen && ! grep -q "^en_US" $T/etc/locale.gen'
check "sudo is for the wheel group, with a safe mode" '[ "$(stat -c %a $T/etc/sudoers.d/10-wheel)" = 440 ] && grep -q "^%wheel ALL=(ALL:ALL) ALL" $T/etc/sudoers.d/10-wheel'
check "fstab has no subvolid and a private EFI partition" '! grep -q subvolid $T/etc/fstab && grep -q "fmask=0077" $T/etc/fstab'
check "the boot entry uses the real root UUID and the bootloader does not allow editing" \
    'grep -q "root=UUID=FAKE-UUID-1234 rootflags=subvol=@ rw" $T/boot/loader/entries/cachyos.conf && grep -q "^editor   no" $T/boot/loader/loader.conf && grep -q "^default  cachyos.conf" $T/boot/loader/loader.conf'
check "root is locked and the user gets wheel; no root password is ever set" \
    'grep -q "arch-chroot .* passwd -l root" "$CMDLOG" && grep -q "useradd -m -G wheel -s /bin/bash tester" "$CMDLOG" && ! grep -q "chpasswd" "$CMDLOG"'
check "only the three services Taurus needs are enabled (no firewall, no bluetooth)" \
    'grep -q "systemctl enable NetworkManager.service systemd-timesyncd.service systemd-boot-update.service" "$CMDLOG" && ! grep -qiE "bluetooth|ufw|firewalld|sshd" "$CMDLOG"'
check "everything is unmounted at the end" 'grep -q "^umount -R $T" "$CMDLOG"'
check "oh-my-bash is cloned into /opt before the user is created" \
    'o="$(awk "/git clone --depth 1 https:\/\/github.com\/ohmybash\/oh-my-bash.git \/opt\/oh-my-bash/{g=NR} /useradd/{u=NR} END{print (g && g<u) ? \"yes\" : \"no\"}" "$CMDLOG")"; [ "$o" = yes ]'
check "the new user's .bashrc (from /etc/skel) loads oh-my-bash from /opt with no theme and a cache in HOME" \
    'grep -q "^export OSH=./opt/oh-my-bash.$" $T/etc/skel/.bashrc && grep -q "^OSH_THEME=\"\"" $T/etc/skel/.bashrc && grep -q "OSH_CACHE_DIR=\"\$HOME/.cache/oh-my-bash\"" $T/etc/skel/.bashrc && bash -n $T/etc/skel/.bashrc'

setup_run nogit
FAIL_GIT_CLONE=1 run_install "ERASE /dev/fake0" --disk /dev/fake0 "${ARGS[@]}"; rc=$?
check "if oh-my-bash cannot be downloaded the install still finishes, without touching .bashrc" \
    '[ "$rc" -eq 0 ] && grep -q "could not download oh-my-bash" "$RUN/out" && grep -q "Remove the ISO and reboot" "$RUN/out" && [ ! -e "$RUN/mnt/etc/skel/.bashrc" ]'

# ---- interactive time zone selection --------------------------------------------------------------------------
setup_run tz
TZ_INPUT="testbox
tester
es_AR.UTF-8
America/Argentina/Buenos_Aires
us
ERASE /dev/fake0"
run_install "$TZ_INPUT" --disk /dev/fake0 --esp-size 1024 --firmware none --copy-network no; rc=$?
check "interactive install lists common zones and accepts an Argentine one" \
    '[ "$rc" -eq 0 ] && grep -q "Common time zones" "$RUN/out" && grep -q "America/Argentina/Buenos_Aires" "$RUN/out" && grep -q "timedatectl list-timezones" "$RUN/out" && grep -q "Locale / tz.*America/Argentina/Buenos_Aires" "$RUN/out"'
check "the chosen time zone is linked into the installed system" \
    '[ "$(readlink "$RUN/mnt/etc/localtime")" = /usr/share/zoneinfo/America/Argentina/Buenos_Aires ]'
setup_run tzflag
run_install "ERASE /dev/fake0" --disk /dev/fake0 "${ARGS[@]}"; rc=$?
check "a time zone given by flag skips the examples" \
    '[ "$rc" -eq 0 ] && ! grep -q "Common time zones" "$RUN/out"'

# ---- full-screen interface (keys fed on stdin) -------------------------------------------------------------------
K_ENTER=$'\n'; K_DOWN=$'\e[B'; K_ESC=$'\e'; K_BS=$'\x7f'
TUI_ARGS=(--tui --locale es_AR.UTF-8 --timezone UTC --keymap us --esp-size 1024)
#        welcome  disk     hostname          user                                         locale   tz       keymap   EFI      firmware
TUI_KEYS="$K_ENTER$K_ENTER${K_BS}${K_BS}${K_BS}${K_BS}${K_BS}${K_BS}${K_BS}box1$K_ENTER$K_ESC${K_ENTER}1x${K_ENTER}$K_BS${K_BS}tester$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER"

setup_run tui
run_install "${TUI_KEYS}${K_ENTER}ERASE /dev/fake0${K_ENTER}" --disk /dev/fake0 "${TUI_ARGS[@]}"; rc=$?
check "the interface installs: wizard, plan, typed confirmation, progress, then the next steps" \
    '[ "$rc" -eq 0 ] && grep -q "Ready to install" "$RUN/out" && grep -q "Installing on /dev/fake0" "$RUN/out" && grep -q "Remove the ISO and reboot" "$RUN/out"'
check "the interface installs the same system as the prompts (host, user, locale, time zone, EFI size)" \
    '[ "$(cat "$RUN/mnt/etc/hostname")" = box1 ] && grep -q "useradd -m -G wheel -s /bin/bash tester" "$CMDLOG" && grep -q "LANG=es_AR.UTF-8" "$RUN/mnt/etc/locale.conf" && [ "$(readlink "$RUN/mnt/etc/localtime")" = /usr/share/zoneinfo/UTC ] && grep -q "size=1024MiB" "$CMDLOG.sfdisk"'
check "the interface rejects an invalid user name and Esc goes back keeping what was typed" \
    'grep -q "\"1x\" is not valid" "$RUN/out" && [ "$(grep -c "useradd" "$CMDLOG")" -eq 1 ]'
check "the interface asks for the password through passwd (it never handles it itself)" \
    'grep -q "arch-chroot .* passwd tester" "$CMDLOG" && grep -q "Password for tester" "$RUN/out" && ! grep -q chpasswd "$CMDLOG"'

setup_run tuiwrong
run_install "${TUI_KEYS}${K_ENTER}erase it${K_ENTER}${K_DOWN}${K_DOWN}${K_ENTER}" --disk /dev/fake0 "${TUI_ARGS[@]}"; rc=$?
check "in the interface a wrong confirmation goes back to the plan and quitting there changes nothing" \
    '[ "$rc" -eq 0 ] && grep -q "Nothing was changed" "$RUN/out" && ! grep -qE "$destructive" "$CMDLOG"'

setup_run tuidry
run_install "${TUI_KEYS}${K_DOWN}${K_ENTER}$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER$K_ENTER" --dry-run "${TUI_ARGS[@]}"; rc=$?
check "in a dry run the interface can go back to change things and then changes nothing" \
    '[ "$rc" -eq 0 ] && grep -q "Dry run finished" "$RUN/out" && [ "$(grep -o "Ready to install" "$RUN/out" | wc -l)" -ge 2 ] && ! grep -qE "$destructive" "$CMDLOG"'

setup_run tuiquit
run_install "${K_DOWN}${K_ENTER}" --tui; rc=$?
check "quitting on the welcome screen changes nothing" '[ "$rc" -eq 0 ] && grep -q "Nothing was changed" "$RUN/out" && [ ! -s "$CMDLOG" ]'

setup_run tuinet
FAKE_CONNECTIONS=1 run_install "${TUI_KEYS}${K_DOWN}${K_ENTER}${K_ENTER}ERASE /dev/fake0${K_ENTER}" --disk /dev/fake0 "${TUI_ARGS[@]}"; rc=$?
check "the interface asks about saved Wi-Fi connections and respects No" \
    '[ "$rc" -eq 0 ] && grep -q "Copy the network connections" "$RUN/out" && ! grep -q "system-connections" "$CMDLOG"'

check "without a terminal (and no --tui) the plain prompts are used" 'grep -q "Common time zones" "$SANDBOX/run-tz/out" && ! grep -q "Ready to install" "$SANDBOX/run-tz/out"'

# ---- the safety net -----------------------------------------------------------------------------------------
setup_run wrong
run_install "yes please" --disk /dev/fake0 "${ARGS[@]}"; rc=$?
check "a wrong confirmation changes nothing" '[ "$rc" -ne 0 ] && ! grep -qE "$destructive" "$CMDLOG"'

setup_run phrase
run_install "ERASE /dev/fake1" --disk /dev/fake0 "${ARGS[@]}"; rc=$?
check "confirming a DIFFERENT disk than the chosen one changes nothing" '[ "$rc" -ne 0 ] && ! grep -qE "$destructive" "$CMDLOG"'

setup_run mounted
FAKE_MOUNTED=1 run_install "ERASE /dev/fake0" --disk /dev/fake0 "${ARGS[@]}"; rc=$?
check "a disk with a mounted partition is refused" '[ "$rc" -ne 0 ] && grep -q "mounted or in use" "$RUN/out" && ! grep -qE "$destructive" "$CMDLOG"'

setup_run part
run_install "ERASE /dev/fake0p1" --disk /dev/fake0p1 "${ARGS[@]}"; rc=$?
check "a partition (not a whole disk) is refused" '[ "$rc" -ne 0 ] && ! grep -qE "$destructive" "$CMDLOG"'

setup_run zram
run_install "ERASE /dev/zram0" --disk /dev/zram0 "${ARGS[@]}"; rc=$?
check "zram and loop devices are never offered" '[ "$rc" -ne 0 ] && ! grep -qE "$destructive" "$CMDLOG"'

setup_run live
stub findmnt '[ "$2" = SOURCE ] || exit 1; [ "$3" = /run/archiso/bootmnt ] && { echo /dev/fake0p3; exit 0; }; exit 1'
FAKE_LIVE_PK=fake0 run_install "ERASE /dev/fake0" --disk /dev/fake0 "${ARGS[@]}"; rc=$?
check "the disk the live ISO booted from is refused" '[ "$rc" -ne 0 ] && grep -q "live ISO booted from" "$RUN/out" && ! grep -qE "$destructive" "$CMDLOG"'
stub findmnt 'exit 1'

setup_run root
run_install "ERASE /dev/fake0" --disk /dev/fake0 --hostname h --user root --locale es_AR.UTF-8 --timezone UTC --keymap us --esp-size 1024 --firmware none; rc=$?
check "the user name 'root' is refused" '[ "$rc" -ne 0 ] && ! grep -qE "$destructive" "$CMDLOG"'

setup_run fw
run_install "ERASE /dev/fake0" --disk /dev/fake0 --hostname h --user u --locale es_AR.UTF-8 --timezone UTC --keymap us --esp-size 1024 --firmware "linux-firmware-amdgpu; rm -rf /"; rc=$?
check "a firmware list with anything but linux-firmware-* names is refused" '[ "$rc" -ne 0 ] && ! grep -qE "$destructive" "$CMDLOG"'

setup_run unresolved
(
    trap - EXIT
    export ISO_TARGET="$RUN/mnt" ISO_LOG="$RUN/log" PATH="$STUBS:$PATH"
    source "$SCRIPT"; set +e
    lspci_nn() { :; }; preflight() { :; }; is_block_device() { [[ "$1" == /dev/fake* ]]; }
    resolve_closure() { echo "error: target not found: nope" >&2; return 1; }
    cpu_vendor() { echo AuthenticAMD; }
    main --disk /dev/fake0 "${ARGS[@]}" <<< "ERASE /dev/fake0"
) > "$RUN/out" 2>&1; rc=$?
check "a package list that does not resolve stops BEFORE anything is erased" '[ "$rc" -ne 0 ] && grep -q "does not resolve" "$RUN/out" && ! grep -qE "$destructive" "$CMDLOG"'

# real preflight on this machine (not root / not a live ISO): must refuse, not proceed
setup_run realcheck
out="$(PATH="$STUBS:$PATH" ISO_LOG="$RUN/log" bash "$SCRIPT" --disk /dev/fake0 "${ARGS[@]}" </dev/null 2>&1)"; rc=$?
check "run for real on a normal system it refuses (not root, not a live ISO)" '[ "$rc" -ne 0 ] && grep -qE "run as root|not a live ISO|missing tool|not booted in UEFI" <<< "$out"'

echo
if [ "$failures" -eq 0 ]; then
    echo "all passed"
else
    echo "$failures failed"
    exit 1
fi
