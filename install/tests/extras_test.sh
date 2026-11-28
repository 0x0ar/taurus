#!/usr/bin/env bash
# extras.sh: tmux config is installed with a backup, and nothing runs unless enabled.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP" XDG_CONFIG_HOME="$TMP/.config" PROJECT_ROOT="$ROOT"
source "$ROOT/install/modules/extras.sh"
fail=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

unset TAURUS_EXTRAS; setup_extras
check "disabled by default" '[ ! -e "$XDG_CONFIG_HOME/tmux/tmux.conf" ]'

command -v tmux >/dev/null && {
  TAURUS_EXTRAS="tmux"; setup_extras >/dev/null
  check "tmux.conf installed" 'cmp -s "$ROOT/config/extras/tmux.conf" "$XDG_CONFIG_HOME/tmux/tmux.conf"'
  echo "# mine" > "$XDG_CONFIG_HOME/tmux/tmux.conf"; setup_extras >/dev/null
  check "existing config is backed up" '[ -f "$XDG_CONFIG_HOME/tmux/tmux.conf.taurus-backup" ]'
}
[ $fail = 0 ] && echo "all extras tests passed"; exit $fail
