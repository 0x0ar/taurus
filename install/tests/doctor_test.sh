#!/usr/bin/env bash
# Tests for `taurus doctor` and the taurusd supervision. Sandbox only: stub quickshell and
# notify-send, private pid/lock files and HOME. The real shell and its settings are never touched.

set -u

REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
SANDBOX="$(mktemp -d)"
STUBS="$SANDBOX/stubs"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$SANDBOX"' EXIT

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
export TAURUS_DIR="$REPO_ROOT/src"
export HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/home/.config" XDG_STATE_HOME="$SANDBOX/home/.local/state"
export XDG_CACHE_HOME="$SANDBOX/home/.cache" XDG_RUNTIME_DIR="$SANDBOX/run"
export QS_SETTINGS="$HOME/.config/taurus/settings.json" QS_STATE_DIR="$HOME/.local/state/taurus"
export TAURUS_PID_FILE="$SANDBOX/taurusd.pid" TAURUS_LOCK_FILE="$SANDBOX/taurusd.lock"
mkdir -p "$HOME/.config/taurus" "$QS_STATE_DIR" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
unset WAYLAND_DISPLAY
export TAURUS_SESSION_GRACE=0.5
DOCTOR="python3 -I $REPO_ROOT/src/scripts/doctor.py"
cp "$REPO_ROOT/config/taurus/settings.json" "$QS_SETTINGS"

# stubs: a quickshell whose behaviour a test controls, and a recording notify-send
cat > "$STUBS/quickshell" <<'EOF'
#!/bin/sh
if [ "$1" = log ]; then cat "$QS_STUB_LOG" 2>/dev/null; exit 0; fi
echo "launch" >> "$QS_STUB_LAUNCHES"
n=$(wc -l < "$QS_STUB_LAUNCHES")
case "$QS_STUB_MODE" in
    die-always) sleep 0.3; exit 1 ;;
    die-once) if [ "$n" -le 1 ]; then sleep 0.3; exit 1; fi; exec sleep 30 ;;
    clean) sleep 0.3; exit 0 ;;
    die-with-helper) if [ "$n" -le 1 ]; then sleep 31 & sleep 0.3; exit 1; fi; exec sleep 30 ;;
    stay) exec sleep 30 ;;
esac
EOF
printf '#!/bin/sh\necho "$@" >> "%s/notifications"\n' "$SANDBOX" > "$STUBS/notify-send"
chmod +x "$STUBS/quickshell" "$STUBS/notify-send"
export QS_STUB_LAUNCHES="$SANDBOX/launches" QS_STUB_LOG="$SANDBOX/qslog"
export PATH="$STUBS:$PATH"

# a process that looks like this install's shell, for the checks that need one
fake_shell() {
    ( exec -a "quickshell -p $TAURUS_DIR/quickshell/Shell.qml" sleep 60 ) &
    FAKE_PID=$!
    sleep 0.3
}
stop_fake_shell() { kill "$FAKE_PID" 2>/dev/null; wait "$FAKE_PID" 2>/dev/null; }

# ---- report ----------------------------------------------------------------------------------
$DOCTOR --json | jq -e '.checks | length > 0' >/dev/null
check "doctor reports without a running shell (warn, not fail)" '[ "$($DOCTOR --json | jq -r ".checks[] | select(.id==\"shell\") | .status")" = warn ]'

echo '{ "bar": ' > "$QS_SETTINGS"      # a settings.json that does not parse
check "invalid settings.json is a failure (exit 2)" '$DOCTOR >/dev/null; [ $? -eq 2 ]'
check "--fix cannot repair it without any backup, and says so" \
    '$DOCTOR --fix | grep -q "no valid backup"; ! jq -e . "$QS_SETTINGS" >/dev/null 2>&1'

mkdir -p "$QS_STATE_DIR/last-good"
cp "$REPO_ROOT/config/taurus/settings.json" "$QS_STATE_DIR/last-good/settings.json"
check "--fix restores the last known good settings" '$DOCTOR --fix | grep -q "restored settings.json" && jq -e .bar "$QS_SETTINGS" >/dev/null'
check "the broken file is kept, not deleted" 'ls "$QS_STATE_DIR"/settings.broken.*.json >/dev/null 2>&1'

# newest valid backup is used when there is no last-good copy
rm -f "$QS_STATE_DIR/last-good/settings.json"
mkdir -p "$QS_STATE_DIR/backups"
echo '{ "bad": ' > "$QS_STATE_DIR/backups/settings.2.json"
echo '{ "from": "backup" }' > "$QS_STATE_DIR/backups/settings.1.json"
touch -d '1 minute ago' "$QS_STATE_DIR/backups/settings.2.json"
echo 'nope' > "$QS_SETTINGS"
$DOCTOR --fix >/dev/null
check "--fix falls back to the newest backup that parses" '[ "$(jq -r .from "$QS_SETTINGS")" = backup ]'
cp "$REPO_ROOT/config/taurus/settings.json" "$QS_SETTINGS"

# stale pid/lock files
echo 999999 > "$TAURUS_PID_FILE"; touch "$TAURUS_LOCK_FILE"
check "stale daemon files are reported as fixable" '[ "$($DOCTOR --json | jq -r ".checks[] | select(.id==\"daemon-files\") | .status")" = warn ]'
$DOCTOR --fix >/dev/null
check "--fix removes the stale pid and lock files" '[ ! -e "$TAURUS_PID_FILE" ] && [ ! -e "$TAURUS_LOCK_FILE" ]'

# a code error in the log must never cause a settings restore
fake_shell
printf '%s\n' ' WARN: something' ' ERROR scene: Type Foo unavailable' ' ERROR quickshell.service.pipewire.loop: Failed to connect pipewire context' > "$QS_STUB_LOG"
before="$(md5sum < "$QS_SETTINGS")"
out="$($DOCTOR --fix --json)"
check "a QML error is reported" 'jq -e ".checks[] | select(.id==\"log\" and .status==\"warn\")" <<< "$out" >/dev/null'
check "a pipewire error is treated as benign" '! jq -r ".checks[] | select(.id==\"log\") | .detail" <<< "$out" | grep -qi pipewire'
check "--fix never touches settings for a QML error" '[ "$(md5sum < "$QS_SETTINGS")" = "$before" ]'

# ---- last known good ---------------------------------------------------------------------------
rm -rf "$QS_STATE_DIR/last-good"
$DOCTOR mark-good
check "mark-good waits until settings have been stable for a minute" '[ ! -e "$QS_STATE_DIR/last-good/settings.json" ]'
touch -d '5 minutes ago' "$QS_SETTINGS"
$DOCTOR mark-good
check "mark-good refuses while the log shows a real error" '[ ! -e "$QS_STATE_DIR/last-good/settings.json" ]'
: > "$QS_STUB_LOG"
$DOCTOR mark-good
check "mark-good saves settings that proved themselves" 'cmp -s "$QS_SETTINGS" "$QS_STATE_DIR/last-good/settings.json"'
stop_fake_shell

# ---- taurusd supervision ------------------------------------------------------------------------
run_daemon() {  # run_daemon <mode> [seconds]: start taurusd with a stub quickshell, then stop it
    : > "$QS_STUB_LAUNCHES"; rm -f "$SANDBOX/notifications" "$QS_STATE_DIR/recovery.json" "$TAURUS_PID_FILE" "$TAURUS_LOCK_FILE"
    QS_STUB_MODE="$1" TAURUS_WATCH_DELAY=2 TAURUS_GOOD_AFTER=300 "$REPO_ROOT/bin/taurusd" start >/dev/null 2>&1 &
    local pid=$!
    sleep "${2:-5}"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    sleep 0.5
}

run_daemon die-always 4
check "a shell that keeps dying is launched exactly twice (one restart), never in a loop" '[ "$(wc -l < "$QS_STUB_LAUNCHES")" -eq 2 ]'
check "giving up leaves a report for the next start" '[ "$(jq -r .restarted "$QS_STATE_DIR/recovery.json")" = false ]'

run_daemon die-once 6
check "a one-off crash restarts the shell once" '[ "$(wc -l < "$QS_STUB_LAUNCHES")" -eq 2 ]'
check "the recovery is announced once the shell is up again" 'grep -q "recovered from a crash" "$SANDBOX/notifications" && [ "$(jq -r .seen "$QS_STATE_DIR/recovery.json")" = true ]'
check "the notification offers a Diagnose action" 'grep -q "diagnose=Diagnose" "$SANDBOX/notifications"'

run_daemon clean 3
check "a clean exit (status 0) is not restarted" '[ "$(wc -l < "$QS_STUB_LAUNCHES")" -eq 1 ]'

WAYLAND_DISPLAY="no-such-socket" run_daemon die-always 3
check "a gone Wayland session is not treated as a crash" '[ "$(wc -l < "$QS_STUB_LAUNCHES")" -eq 1 ]'

# the crashed shell's helpers must not outlive it
run_daemon die-with-helper 5
check "the crashed shell's leftover helpers are ended before the restart" '! pgrep -f "^sleep 31$" >/dev/null'

# logout race: the shell dies a moment before the compositor's socket disappears
: > "$QS_STUB_LAUNCHES"; rm -f "$QS_STATE_DIR/recovery.json" "$TAURUS_PID_FILE" "$TAURUS_LOCK_FILE"
python3 -c "import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); time.sleep(30)" "$XDG_RUNTIME_DIR/wl-test" &
SOCK_PID=$!
sleep 0.4
WAYLAND_DISPLAY=wl-test QS_STUB_MODE=die-always TAURUS_SESSION_GRACE=1.5 TAURUS_WATCH_DELAY=300 "$REPO_ROOT/bin/taurusd" start >/dev/null 2>&1 &
dpid=$!
sleep 0.9
rm -f "$XDG_RUNTIME_DIR/wl-test"        # the session ends while the daemon is still waiting
sleep 3
kill "$dpid" "$SOCK_PID" 2>/dev/null; wait "$dpid" 2>/dev/null
check "a session that ends during the grace period is not restarted" '[ "$(wc -l < "$QS_STUB_LAUNCHES")" -eq 1 ]'
check "and it leaves no false crash report for the next login" '[ ! -e "$QS_STATE_DIR/recovery.json" ]'

# taurus kill must end the daemon, not restart the shell
: > "$QS_STUB_LAUNCHES"; rm -f "$TAURUS_PID_FILE" "$TAURUS_LOCK_FILE"
QS_STUB_MODE=stay TAURUS_WATCH_DELAY=300 "$REPO_ROOT/bin/taurusd" start >/dev/null 2>&1 &
dpid=$!
sleep 3
kill -TERM "$dpid" 2>/dev/null
sleep 1.5
check "stopping the daemon does not relaunch the shell" '[ "$(wc -l < "$QS_STUB_LAUNCHES")" -eq 1 ] && ! kill -0 "$dpid" 2>/dev/null'
wait "$dpid" 2>/dev/null

# a settings.json that does not parse is repaired before the shell starts
echo '{ broken' > "$QS_SETTINGS"
mkdir -p "$QS_STATE_DIR/last-good"; cp "$REPO_ROOT/config/taurus/settings.json" "$QS_STATE_DIR/last-good/settings.json"
run_daemon stay 3
check "preflight repairs invalid settings before launching" 'jq -e .bar "$QS_SETTINGS" >/dev/null'

echo
if [ "$failures" -eq 0 ]; then
    echo "all passed"
else
    echo "$failures failed"
    exit 1
fi
