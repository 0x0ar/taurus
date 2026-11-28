#!/usr/bin/env bash
# AI coding clients the settings page can install, and the Taurus skills for them.
#   ai-clients.sh status            JSON list of the clients and whether each is installed
#   ai-clients.sh install <id>      install one client when it is missing (root through pkexec)
#   ai-clients.sh skills            link the Taurus skills where the clients look for them
#   ai-clients.sh models            seed Claude Code's model routing in its settings.json
# Skills go to each client's own folder and to ~/.agents/skills (see `taurus agent skills status`).

# id|name|command|repo package
CLIENTS=(
    "claude|Claude Code|claude|claude-code"
    "codex|Codex|codex|openai-codex"
    "opencode|OpenCode|opencode|opencode"
    "gemini|Gemini CLI|gemini|gemini-cli"
)

die() { echo "ai-clients: $*" >&2; exit 1; }

find_client() {
    local row
    for row in "${CLIENTS[@]}"; do
        [ "${row%%|*}" = "$1" ] && { echo "$row"; return 0; }
    done
    return 1
}

have_cmd() { command -v "$1" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$1" ]; }

# Where each client looks for skills (the same folders `taurus agent skills` links into)
client_skills_dir() {
    case "$1" in
        claude) echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" ;;
        codex) echo "${CODEX_HOME:-$HOME/.codex}/skills" ;;
        gemini) echo "$HOME/.gemini/skills" ;;
        opencode) echo "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" ;;
    esac
}
client_skills_linked() { [ -e "$(client_skills_dir "$1")/taurus" ]; }

# Claude Code model routing: Sonnet for everyday work, Opus only when the advisor is
# asked, Haiku as the default for simple delegated tasks. Do not force it onto every
# subagent: a per-task model or a subagent's own `model` field must still be able to
# pick Sonnet/Opus for work that needs it. Existing settings always win.
CLAUDE_MODEL_DEFAULTS='{"model":"sonnet","advisorModel":"opus","env":{"CLAUDE_CODE_SUBAGENT_MODEL":"haiku"}}'

claude_settings_file() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; }

configure_claude_models() {
    local file dir tmp merged
    file="$(claude_settings_file)"
    dir="$(dirname "$file")"

    if [ -e "$file" ] && ! jq -e . "$file" >/dev/null 2>&1; then
        echo "ai-clients: $file is not valid JSON; leaving your Claude Code settings alone" >&2
        return 1
    fi

    if [ -f "$file" ]; then
        merged="$(jq --argjson defaults "$CLAUDE_MODEL_DEFAULTS" '
            . as $user
            | $defaults as $def
            | ($def + $user)
            | .env = ($def.env + (if ($user.env | type) == "object" then $user.env else {} end))
        ' "$file")" || {
            echo "ai-clients: could not merge $file" >&2
            return 1
        }
    else
        merged="$(jq -n --argjson defaults "$CLAUDE_MODEL_DEFAULTS" '$defaults')"
    fi

    mkdir -p "$dir" || return 1
    tmp="$(mktemp "$dir/.settings.XXXXXX")" || return 1
    if printf '%s\n' "$merged" >"$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$file"; then
        echo "Claude Code models: Sonnet base, Opus advisor, Haiku tasks"
    else
        rm -f "$tmp"
        echo "ai-clients: could not write $file" >&2
        return 1
    fi
}

cmd_status() {
    local row id name bin pkg installed repo skills
    for row in "${CLIENTS[@]}"; do
        IFS='|' read -r id name bin pkg <<<"$row"
        installed=false; have_cmd "$bin" && installed=true
        repo=false; pacman -Si "$pkg" >/dev/null 2>&1 && repo=true
        skills=false; client_skills_linked "$id" && skills=true
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$installed" "$repo" "$pkg" "$skills"
    done | jq -Rn '
        [inputs | split("\t") | {id: .[0], name: .[1], installed: (.[2] == "true"),
                                 repo: (.[3] == "true"), package: .[4], skills: (.[5] == "true")}]'
}

cmd_install() {
    local row id name bin pkg
    row="$(find_client "${1:-}")" || die "unknown client: ${1:-}"
    IFS='|' read -r id name bin pkg <<<"$row"
    if have_cmd "$bin"; then echo "$name is already installed"; return 0; fi

    if pacman -Si "$pkg" >/dev/null 2>&1; then
        echo "Installing $pkg with pacman"
        pkexec pacman -S --needed --noconfirm "$pkg" || die "pacman could not install $pkg"
    elif [ "$id" = claude ]; then
        echo "Installing Claude Code with its own installer (no root needed)"
        curl -fsSL https://claude.ai/install.sh | bash || die "the Claude Code installer failed"
    else
        die "$pkg is not in the enabled repositories"
    fi
    have_cmd "$bin" || die "$name was installed but '$bin' is not on PATH"
    [ "$id" = claude ] && configure_claude_models
    echo "$name installed"
}

cmd_skills() {
    local taurus
    taurus="$(command -v taurus || true)"; [ -n "$taurus" ] || taurus="$HOME/.local/bin/taurus"
    "$taurus" agent skills install || return 1
    # The launcher installs the clients and links the skills in one pass: set up the
    # model routing in the same pass, even when Claude Code was already installed.
    have_cmd claude && configure_claude_models
    return 0
}

case "${1:-}" in
    status) cmd_status ;;
    install) shift; cmd_install "$@" ;;
    skills) cmd_skills ;;
    models) configure_claude_models ;;
    *) echo "usage: ai-clients.sh <status|install <id>|skills|models>" >&2; exit 2 ;;
esac
