#!/usr/bin/env bash
# Tests for the agent-facing CLI: command registry, config backups, skills and their install.
# Everything runs in a sandbox HOME; the real home and the user's shell are never touched.

set -u

REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
TAURUS="$REPO_ROOT/bin/taurus"
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
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="$SANDBOX/run"
mkdir -p "$HOME/.config/taurus" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
unset TAURUS_DIR QS_SETTINGS QS_STATE_DIR QS_CACHE_DIR QS_RUN_DIR QS_LOG_DIR TAURUS_BUS_ENV CLAUDE_CONFIG_DIR
cp "$REPO_ROOT/config/taurus/settings.json" "$HOME/.config/taurus/settings.json"

# ---- registry ------------------------------------------------------------------------
check "taurus commands prints a table" '"$TAURUS" commands | grep -q "^COMMAND"'
check "taurus commands --json is valid with risk levels" \
    '"$TAURUS" commands --json | jq -e "[.commands[].risk] | all(. == \"read\" or . == \"change\" or . == \"disruptive\")" >/dev/null'
check "taurus info paths --json reports the install and log dirs" \
    '"$TAURUS" info paths --json | jq -e ".install_dir and .log_dir and .user_themes and (.install_dir_read_only | type == \"boolean\")" >/dev/null'

drift="$(python3 -I - "$REPO_ROOT" <<'PY'
import json, re, sys
root = sys.argv[1]
src = open(f"{root}/bin/taurus").read()
a = set(re.findall(r'\[\[ "\$1" == "([a-z_-]+)" \]\]', src))
case = src[src.index('case "$1" in\n    config)'):src.index("ALLOWED_SCRIPTS=(")]
b = set(re.findall(r"^    ([a-z_-]+)\)$", case, re.M))
c = set(re.findall(r'"([a-z_-]+)"', src[src.index("ALLOWED_SCRIPTS=("):src.index('COMMAND="$1"')]))
handled = {x for x in a | b | c if not x.startswith("-")} - {"workspace"}
reg = {x["name"] for x in json.load(open(f"{root}/src/assets/cli-commands.json"))["commands"]}
problems = [f"not in registry: {x}" for x in sorted(handled - reg)] + [f"not handled by bin/taurus: {x}" for x in sorted(reg - handled)]
print("\n".join(problems))
PY
)"
check "every command in bin/taurus is in the registry, and the reverse" '[ -z "$drift" ]'
[ -n "$drift" ] && echo "$drift" | sed 's/^/      /'

# ---- skills content ----------------------------------------------------------------------
skills_problems="$(python3 -I - "$REPO_ROOT" <<'PY'
import glob, json, os, re, sys
root = sys.argv[1]
reg = {x["name"] for x in json.load(open(f"{root}/src/assets/cli-commands.json"))["commands"]}
problems = []
for skill in sorted(glob.glob(f"{root}/src/agents/skills/*/SKILL.md")):
    name = os.path.basename(os.path.dirname(skill))
    text = open(skill).read()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        problems.append(f"{name}: no frontmatter"); continue
    fm = dict(re.findall(r"^(\w[\w-]*):\s*(.*)$", m.group(1), re.M))
    if fm.get("name") != name:
        problems.append(f"{name}: name must equal the folder name")
    d = fm.get("description", "")
    if not d or len(d) > 1536 or "<" in d or ">" in d:
        problems.append(f"{name}: bad description")
    if text.count("\n") > 500:
        problems.append(f"{name}: SKILL.md is over 500 lines")
# every `taurus <command>` shown in code must be a real command
for md in sorted(glob.glob(f"{root}/src/agents/skills/**/*.md", recursive=True)):
    text = open(md).read()
    code = re.findall(r"```[a-z]*\n(.*?)```", text, re.S) + re.findall(r"`([^`\n]+)`", text)
    for chunk in code:
        for line in chunk.splitlines():
            if line.lstrip().startswith("#"):
                continue  # comments inside code blocks, e.g. the theme markers
            for cmd in re.findall(r"(?:^|[\s$(;|])taurus\s+([a-z][a-z_-]*)", line):
                if cmd not in reg:
                    problems.append(f"{os.path.relpath(md, root)}: unknown command 'taurus {cmd}'")
print("\n".join(sorted(set(problems))))
PY
)"
check "skills have valid frontmatter and only teach real commands" '[ -z "$skills_problems" ]'
[ -n "$skills_problems" ] && echo "$skills_problems" | sed 's/^/      /'
check "skill reference guides match docs/" 'python3 -I "$REPO_ROOT/tools/sync-skill-docs.py" --check >/dev/null'

# ---- config backups, reset, diff, restore ---------------------------------------------------
"$TAURUS" config set bar.height 52 >/dev/null 2>&1
check "config set writes the value" '[ "$("$TAURUS" config get bar.height)" = 52 ]'
check "config set made a backup" '[ "$("$TAURUS" config backups | wc -l)" -ge 1 ]'
check "config diff shows the change" '"$TAURUS" config diff | grep -q "^+    \"height\": 52"'
check "config set warns about unknown keys without blocking" \
    '"$TAURUS" config set not.a.real.key 1 2>&1 | grep -q "not in the shipped defaults" && [ "$("$TAURUS" config get not.a.real.key)" = 1 ]'
"$TAURUS" config reset bar.height >/dev/null 2>&1
"$TAURUS" config reset not.a.real.key >/dev/null 2>&1
check "config reset restores the shipped default" '[ "$("$TAURUS" config get bar.height)" = 40 ]'
check "config reset removes a key with no default" '[ "$("$TAURUS" config get not.a.real.key gone)" = gone ]'
"$TAURUS" config set bar.height 99 >/dev/null 2>&1
"$TAURUS" config restore latest >/dev/null 2>&1
check "config restore undoes the last write" '[ "$("$TAURUS" config get bar.height)" = 40 ]'
check "config restore rejects a missing backup" '! "$TAURUS" config restore /nonexistent 2>/dev/null'
for i in $(seq 1 25); do "$TAURUS" config set bar.opacity "$((50 + i))" >/dev/null 2>&1; done
check "backups are rotated to the newest 20" '[ "$("$TAURUS" config backups | wc -l)" -le 20 ]'

# ---- an installer-shaped tree (bin/ and src/ only, as the one-line installer deploys it) ----
INST_ROOT="$HOME/.local/share/taurus"
mkdir -p "$INST_ROOT"
cp -r "$REPO_ROOT/bin" "$INST_ROOT/bin"
cp -r "$REPO_ROOT/src" "$INST_ROOT/src"
INST_TAURUS="$INST_ROOT/bin/taurus"
check "the installer layout has no sibling config/" '[ ! -e "$INST_ROOT/config" ]'
check "info paths points at defaults that exist on that layout" \
    '[ -f "$("$INST_TAURUS" info paths --json | jq -r .settings_defaults)" ]'
"$INST_TAURUS" config set bar.height 77 >/dev/null 2>&1
check "config diff works on the installer layout" '"$INST_TAURUS" config diff | grep -q "^+    \"height\": 77"'
"$INST_TAURUS" config reset bar.height >/dev/null 2>&1
check "config reset restores the default on the installer layout" '[ "$("$INST_TAURUS" config get bar.height)" = 40 ]'
rm -rf "$INST_ROOT"

check "config backup makes a backup on demand" '"$TAURUS" config backup >/dev/null && [ "$("$TAURUS" config backups | wc -l)" -ge 1 ]'
check "share export writes valid JSON to stdout" '"$TAURUS" share export -o - 2>/dev/null | jq -e ".format == \"taurus-setup\"" >/dev/null'
check "share import is a preview unless --apply is given" \
    '"$TAURUS" share export -o "$SANDBOX/s.json" 2>/dev/null; before="$(md5sum < "$HOME/.config/taurus/settings.json")"; "$TAURUS" share import "$SANDBOX/s.json" | grep -q "preview" && [ "$(md5sum < "$HOME/.config/taurus/settings.json")" = "$before" ]'

# ---- user themes can be applied by name -----------------------------------------------------
mkdir -p "$XDG_STATE_HOME/taurus/themes"
jq '.name = "SandboxTheme"' "$REPO_ROOT/src/assets/themes/Taurus.json" > "$XDG_STATE_HOME/taurus/themes/SandboxTheme.json"
check "info theme lists user presets" '"$TAURUS" info theme presets | grep -qx SandboxTheme'

# ---- skills install --------------------------------------------------------------------------
INSTALLED="$HOME/.local/share/taurus/src"
mkdir -p "$INSTALLED/agents"
cp -r "$REPO_ROOT/src/agents/skills" "$INSTALLED/agents/skills"
AGENT="$REPO_ROOT/src/scripts/agent.sh"
n_skills="$(find "$INSTALLED/agents/skills" -maxdepth 2 -name SKILL.md | wc -l)"

check "skills install refuses a git checkout" 'TAURUS_DIR="$REPO_ROOT/src" bash "$AGENT" skills install 2>&1 | grep -q "refusing to link"'
mkdir -p "$HOME/.cache/x/src/agents" && cp -r "$REPO_ROOT/src/agents/skills" "$HOME/.cache/x/src/agents/skills"
check "skills install refuses a cache folder" \
    'TAURUS_DIR="$HOME/.cache/x/src" bash "$AGENT" skills install 2>&1 | grep -q "refusing to link"'
export TAURUS_DIR="$INSTALLED"
# targets: the two shared folders plus one per client installed on this machine (codex, gemini, opencode)
n_targets="$(bash "$AGENT" skills status --json | jq '[.[].target] | unique | length')"
check "skills install links every skill into both agent folders" \
    'bash "$AGENT" skills install >/dev/null && [ "$(find "$HOME/.claude/skills" "$HOME/.agents/skills" -maxdepth 1 -type l | wc -l)" -eq $((n_skills * 2)) ]'
check "linked skills resolve to the installed copy" \
    '[ "$(realpath "$HOME/.claude/skills/taurus")" = "$(realpath "$INSTALLED/agents/skills/taurus")" ]'
check "installing twice is idempotent" 'bash "$AGENT" skills install | grep -vq "unchanged" ; [ "$(bash "$AGENT" skills install | grep -c unchanged)" -eq $((n_skills * n_targets)) ]'
check "status reports linked" '[ "$(bash "$AGENT" skills status --json | jq "[.[] | select(.state == \"linked\")] | length")" -eq $((n_skills * n_targets)) ]'

FAKEBIN="$(mktemp -d)"; printf '#!/bin/sh\n' > "$FAKEBIN/codex"; chmod +x "$FAKEBIN/codex"
check "an installed codex gets its own skills folder" \
    'PATH="$FAKEBIN:$PATH" bash "$AGENT" skills install >/dev/null && [ -L "$HOME/.codex/skills/taurus" ]'

# a skill folder of the user's own must win and survive uninstall
rm -f "$HOME/.claude/skills/taurus-diagnose"
mkdir -p "$HOME/.claude/skills/taurus-diagnose"
echo mine > "$HOME/.claude/skills/taurus-diagnose/SKILL.md"
check "a folder of the user's own is never replaced" \
    'bash "$AGENT" skills install | grep -q "taurus-diagnose: skipped" && [ "$(cat "$HOME/.claude/skills/taurus-diagnose/SKILL.md")" = mine ]'
check "uninstall removes only Taurus links" \
    'bash "$AGENT" skills uninstall >/dev/null; [ ! -e "$HOME/.claude/skills/taurus" ] && [ ! -e "$HOME/.agents/skills/taurus-diagnose" ] && [ "$(cat "$HOME/.claude/skills/taurus-diagnose/SKILL.md")" = mine ]'
check "CLAUDE_CONFIG_DIR is respected" \
    'CLAUDE_CONFIG_DIR="$SANDBOX/claude" bash "$AGENT" skills install >/dev/null && [ -L "$SANDBOX/claude/skills/taurus" ]'
unset TAURUS_DIR

# ---- no side effects on the user's systemd / D-Bus environment --------------------------------
mkdir -p "$SANDBOX/stubs"
printf '#!/bin/sh\necho "$@" >> "%s/dbus-calls"\n' "$SANDBOX" > "$SANDBOX/stubs/dbus-update-activation-environment"
chmod +x "$SANDBOX/stubs/dbus-update-activation-environment"
PATH="$SANDBOX/stubs:$PATH" "$TAURUS" commands >/dev/null 2>&1
PATH="$SANDBOX/stubs:$PATH" "$TAURUS" info paths >/dev/null 2>&1
check "the CLI never touches the D-Bus activation environment" '[ ! -s "$SANDBOX/dbus-calls" ]'
PATH="$SANDBOX/stubs:$PATH" TAURUS_BUS_ENV=1 TAURUS_DIR="$REPO_ROOT/src" bash -c 'source "$TAURUS_DIR/scripts/caching.sh"' >/dev/null 2>&1
check "the daemon still exports TAURUS_DIR when asked to" 'grep -q "TAURUS_DIR" "$SANDBOX/dbus-calls"'
# a fake quickshell records any attempt to start the shell; the read-only commands must not
printf '#!/bin/sh\necho started >> "%s/quickshell-calls"\n' "$SANDBOX" > "$SANDBOX/stubs/quickshell"
chmod +x "$SANDBOX/stubs/quickshell"
for c in "commands" "commands --json" "info paths" "agent skills status" "config diff" "config backups" "config dump" "doctor" "doctor --json" "share export -o -" "scene list" "scene status" "scene show work"; do
    # shellcheck disable=SC2086
    PATH="$SANDBOX/stubs:$PATH" TAURUS_DIR="$INSTALLED" "$TAURUS" $c >/dev/null 2>&1
done
sleep 1
check "the agent commands never start the shell" '[ ! -s "$SANDBOX/quickshell-calls" ]'

echo
if [ "$failures" -eq 0 ]; then
    echo "all passed"
else
    echo "$failures failed"
    exit 1
fi
