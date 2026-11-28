#!/usr/bin/env bash
# Tests for the AI clients helper: Claude Code model routing, in a sandbox HOME.
# The real home and the user's running shell are never touched.

set -u

REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
SCRIPT="$REPO_ROOT/src/scripts/ai-clients.sh"
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

export HOME="$SANDBOX/home"
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME"
SETTINGS="$HOME/.claude/settings.json"

# ---- a fresh Claude Code configuration --------------------------------------------------
"$SCRIPT" models >/dev/null
check "seeds the token-efficient routing" \
    'jq -e ".model == \"sonnet\" and .advisorModel == \"opus\" and .env.CLAUDE_CODE_SUBAGENT_MODEL == \"haiku\" and (.env | has(\"CLAUDE_CODE_SUBAGENT_MODEL_FORCE\") | not)" "$SETTINGS" >/dev/null'
check "keeps the settings file private" '[ "$(stat -c %a "$SETTINGS")" = 600 ]'
cp "$SETTINGS" "$SANDBOX/before.json"
"$SCRIPT" models >/dev/null
check "leaves an already configured file unchanged" 'cmp -s "$SETTINGS" "$SANDBOX/before.json"'

# ---- the user's own choices win -----------------------------------------------------------
cat >"$SETTINGS" <<'EOF'
{"model":"opus","theme":"dark","env":{"MY_VAR":"kept","CLAUDE_CODE_SUBAGENT_MODEL":"sonnet"}}
EOF
"$SCRIPT" models >/dev/null
check "preserves the user's model and unrelated keys" \
    'jq -e ".model == \"opus\" and .theme == \"dark\" and .env.MY_VAR == \"kept\"" "$SETTINGS" >/dev/null'
check "adds only the missing routing keys" \
    'jq -e ".advisorModel == \"opus\" and .env.CLAUDE_CODE_SUBAGENT_MODEL == \"sonnet\" and (.env | has(\"CLAUDE_CODE_SUBAGENT_MODEL_FORCE\") | not)" "$SETTINGS" >/dev/null'

# ---- an explicit user override is never undone --------------------------------------------
rm -rf "$HOME/.claude"
mkdir -p "$HOME/.claude"
printf '%s\n' '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL_FORCE":"1"}}' >"$SETTINGS"
"$SCRIPT" models >/dev/null
check "keeps an explicit force-Haiku choice" \
    'jq -e ".env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE == \"1\" and .env.CLAUDE_CODE_SUBAGENT_MODEL == \"haiku\"" "$SETTINGS" >/dev/null'

# ---- a custom Claude Code config dir -----------------------------------------------------
rm -rf "$HOME/.claude"
export CLAUDE_CONFIG_DIR="$SANDBOX/custom-claude"
"$SCRIPT" models >/dev/null
check "honors CLAUDE_CONFIG_DIR" \
    'jq -e ".model == \"sonnet\"" "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null'
check "does not fall back to the default folder" '[ ! -e "$HOME/.claude/settings.json" ]'

# ---- never clobber a broken file ----------------------------------------------------------
printf 'not json\n' >"$CLAUDE_CONFIG_DIR/settings.json"
check "reports an invalid settings file" '! "$SCRIPT" models >/dev/null 2>&1'
check "leaves the invalid file untouched" '[ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = "not json" ]'

if [ "$failures" -gt 0 ]; then
    echo "$failures test(s) failed"
    exit 1
fi
echo "all tests passed"
