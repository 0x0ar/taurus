#!/usr/bin/env bash
# Agent-facing helpers behind `taurus commands`, `taurus info paths` and `taurus agent`.
#
# None of these start the daemon or touch the running shell: an agent diagnosing a dead
# shell must be able to use them. The only writes are the skill symlinks (`agent skills`).

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
: "${TAURUS_DIR:=$(dirname "$SCRIPT_DIR")}"
export TAURUS_DIR
source "$SCRIPT_DIR/caching.sh"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/i18n.sh"

REGISTRY="$TAURUS_DIR/assets/cli-commands.json"

die() { echo "taurus: $*" >&2; exit 1; }

# ---- taurus commands [--json] ----------------------------------------------------------

agent_commands() {
    [ -f "$REGISTRY" ] || die "command registry not found at $REGISTRY"
    if [ "${1:-}" = "--json" ]; then
        jq . "$REGISTRY"
        return
    fi
    jq -r '.commands[] | [.name, .risk, .description] | @tsv' "$REGISTRY" \
        | awk -F'\t' 'BEGIN { printf "%-16s %-11s %s\n", "COMMAND", "RISK", "DESCRIPTION" }
                      { printf "%-16s %-11s %s\n", $1, $2, $3 }'
    echo
    echo "Risk levels: read = safe, change = reversible, disruptive = ask the user first."
    echo "Details: taurus commands --json   |   usage: taurus <command> --help"
}

# ---- taurus info paths [--json] --------------------------------------------------------

# package: installed by pacman (read-only); user: installer copy; checkout: a git working tree.
install_kind() {
    local d="$1"
    case "$d" in
        /usr/*) echo package; return ;;
        "$HOME"/.local/share/taurus/*) echo user; return ;;
    esac
    local up="$d"
    while [ "$up" != "/" ] && [ -n "$up" ]; do
        [ -e "$up/.git" ] && { echo checkout; return; }
        up="$(dirname "$up")"
    done
    echo unknown
}

agent_paths() {
    local kind version
    kind="$(install_kind "$TAURUS_DIR")"
    version="$(cat "$TAURUS_DIR/version.txt" 2>/dev/null || cat "$(dirname "$TAURUS_DIR")/version.txt" 2>/dev/null || echo unknown)"
    local json
    json="$(jq -n \
        --arg install_dir "$TAURUS_DIR" --arg kind "$kind" --arg version "$version" \
        --arg settings "$CONFIG_SETTINGS_JSON" --arg defaults "$(config_defaults_path)" \
        --arg backups "$(config_backup_dir)" --arg state "$QS_STATE_DIR" --arg cache "$QS_CACHE_DIR" \
        --arg run "$QS_RUN_DIR" --arg logs "$QS_LOG_DIR" \
        --arg user_themes "$QS_STATE_DIR/themes" --arg bundled_themes "$TAURUS_DIR/assets/themes" \
        --arg user_apps "${XDG_CONFIG_HOME:-$HOME/.config}/taurus/matugen/apps" \
        --arg bundled_apps "$TAURUS_DIR/assets/matugen/apps" --arg skills "$TAURUS_DIR/agents/skills" \
        --arg user_scenes "${XDG_CONFIG_HOME:-$HOME/.config}/taurus/scenes" --arg bundled_scenes "$TAURUS_DIR/assets/scenes" \
        --arg last_good "$QS_STATE_DIR/last-good/settings.json" --arg recovery "$QS_STATE_DIR/recovery.json" \
        '{install_dir: $install_dir, install_kind: $kind, install_dir_read_only: ($kind == "package"),
          version: $version, settings: $settings, settings_defaults: $defaults, settings_backups: $backups,
          state_dir: $state, cache_dir: $cache, run_dir: $run, log_dir: $logs,
          user_themes: $user_themes, bundled_themes: $bundled_themes,
          user_matugen_apps: $user_apps, bundled_matugen_apps: $bundled_apps, skills: $skills,
          user_scenes: $user_scenes, bundled_scenes: $bundled_scenes, last_good_settings: $last_good,
          recovery_report: $recovery}')"
    if [ "${1:-}" = "--json" ]; then
        jq . <<< "$json"
    else
        jq -r 'to_entries[] | "\(.key): \(.value)"' <<< "$json"
    fi
}

# ---- taurus agent skills <install|uninstall|status> -----------------------------------

# Agent harnesses that read SKILL.md folders. The user's own folders always win.
skill_targets() {
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" "$HOME/.agents/skills"
    # Clients with a folder of their own, only when they are installed
    if command -v codex >/dev/null 2>&1; then printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/skills"; fi
    if command -v gemini >/dev/null 2>&1; then printf '%s\n' "$HOME/.gemini/skills"; fi
    if command -v opencode >/dev/null 2>&1; then printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"; fi
}

skills_source() {
    local src="$TAURUS_DIR/agents/skills"
    [ -d "$src" ] || die "no skills found at $src"
    realpath "$src"
}

# Refuse to link into places that do not survive an update (cache, a dev checkout).
skills_source_is_stable() {
    local src="$1"
    case "$src" in
        "$HOME"/.cache/*|"${XDG_CACHE_HOME:-$HOME/.cache}"/*) return 1 ;;
    esac
    [ "$(install_kind "$src")" != checkout ]
}

# Name of every skill we ship (directories that hold a SKILL.md).
skill_names() {
    local src="$1" d
    for d in "$src"/*/; do
        [ -f "${d}SKILL.md" ] && basename "$d"
    done
}

# Is this symlink one of ours (current or from a previous install location)?
is_our_link() {
    local link="$1" name="$2" dest
    [ -L "$link" ] || return 1
    dest="$(readlink "$link")"
    [[ "$dest" == */agents/skills/"$name" ]]
}

skills_install() {
    local force=false json=false
    for a in "$@"; do
        case "$a" in
            --force-path) force=true ;;
            --json) json=true ;;
        esac
    done
    local src
    src="$(skills_source)" || exit 1
    if ! skills_source_is_stable "$src" && [ "$force" != true ]; then
        die "refusing to link skills from $src (a cache or a git checkout does not survive updates). Install Taurus first, or pass --force-path to link it anyway."
    fi
    local results="[]" target name link status
    while IFS= read -r target; do
        for name in $(skill_names "$src"); do
            link="$target/$name"
            if [ -L "$link" ] && [ "$(realpath -m "$link")" = "$src/$name" ]; then
                status=unchanged
            elif is_our_link "$link" "$name"; then
                ln -sfn "$src/$name" "$link" && status=updated || status=error
            elif [ -e "$link" ] || [ -L "$link" ]; then
                status="skipped (your own '$name' takes precedence)"
            else
                mkdir -p "$target" && ln -s "$src/$name" "$link" && status=linked || status=error
            fi
            results="$(jq -c --arg t "$target" --arg n "$name" --arg s "$status" '. + [{target: $t, skill: $n, status: $s}]' <<< "$results")"
        done
    done < <(skill_targets)
    if [ "$json" = true ]; then jq . <<< "$results"; else
        jq -r '.[] | "\(.target)/\(.skill): \(.status)"' <<< "$results"
    fi
}

skills_uninstall() {
    local name target link removed=0
    while IFS= read -r target; do
        for link in "$target"/taurus*; do
            [ -L "$link" ] || continue
            name="$(basename "$link")"
            if is_our_link "$link" "$name"; then
                rm -f -- "$link" && { echo "removed $link"; removed=$((removed + 1)); }
            fi
        done
    done < <(skill_targets)
    [ "$removed" -gt 0 ] || echo "nothing to remove"
}

skills_status() {
    local json=false
    [ "${1:-}" = "--json" ] && json=true
    local src results="[]" target name link state
    src="$(skills_source)" || exit 1
    while IFS= read -r target; do
        for name in $(skill_names "$src"); do
            link="$target/$name"
            if [ -L "$link" ] && [ "$(realpath -m "$link")" = "$src/$name" ]; then state=linked
            elif is_our_link "$link" "$name"; then state="stale (points to $(readlink "$link"))"
            elif [ -e "$link" ] || [ -L "$link" ]; then state="other (yours)"
            else state=missing; fi
            results="$(jq -c --arg t "$target" --arg n "$name" --arg s "$state" '. + [{target: $t, skill: $n, state: $s}]' <<< "$results")"
        done
    done < <(skill_targets)
    if [ "$json" = true ]; then jq . <<< "$results"; else
        jq -r '.[] | "\(.target)/\(.skill): \(.state)"' <<< "$results"
    fi
}

agent_usage() {
    echo "usage: taurus agent skills <install|uninstall|status> [--json] [--force-path]" >&2
    exit 1
}

case "${1:-}" in
    commands) shift; agent_commands "$@" ;;
    paths) shift; agent_paths "$@" ;;
    skills)
        shift
        case "${1:-}" in
            install) shift; skills_install "$@" ;;
            uninstall) shift; skills_uninstall "$@" ;;
            status) shift; skills_status "$@" ;;
            *) agent_usage ;;
        esac
        ;;
    *) agent_usage ;;
esac
