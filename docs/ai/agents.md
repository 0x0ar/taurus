---
sidebar_position: 1
title: AI agents
sidebar_label: AI agents
slug: /ai/agents
---

# AI agents

Taurus ships **skills**: small folders that teach an AI coding agent (Claude Code, or any agent that reads `~/.agents/skills`) how to customize, theme and troubleshoot *this* desktop. The idea is simple: the agent gets a stable, self-documenting command (`taurus`), a map of where everything lives, and a short list of rules, so it changes your setup the way you would.

The skills are guidance, not magic. They work best when you run the agent in plan mode first and read what it proposes.

## Install

```bash
taurus agent skills install
taurus agent skills status
```

This links the Taurus skills into `~/.claude/skills` (or `$CLAUDE_CONFIG_DIR/skills`) and `~/.agents/skills`. Links point to the installed copy, so updating Taurus updates the skills. A skill folder of your own with the same name is never replaced, and `taurus agent skills uninstall` removes only the links Taurus created. Then restart your agent and check that the skills appear (in Claude Code, type `/` and look for `taurus`).

Taurus refuses to link from a cache folder or a git checkout, because those do not survive updates. Pass `--force-path` if you really want that.

### From the settings

**Settings → AI clients** (`Mod+H`) lists Claude Code, Codex, OpenCode and Gemini CLI. Tick the ones that are not installed yet and press **Install selected**: Taurus installs each from the repositories with `pkexec pacman` (Claude Code falls back to its own installer when your repositories do not carry it), then links the skills above for all of them. Clients that are already installed are only marked as such.

### Model routing for Claude Code

Installing Claude Code from this page, or linking its skills, also seeds `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`) with a token-efficient setup:

| Setting | Value | Use |
| --- | --- | --- |
| `model` | `sonnet` | Main conversation: enough for everyday coding without paying for Opus on every message. |
| `advisorModel` | `opus` | The server-side advisor, called only for the hard questions. |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `haiku` | Default for simple delegated tasks, which do not need a frontier model. |

Haiku is a default, not a rule: a model chosen for a single task, or a subagent with its own `model` field, still wins, so complex work can run on Sonnet or Opus. The built-in Explore and Plan subagents keep the main conversation's model. Taurus deliberately does **not** set `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, which would force Haiku onto every subagent; if you set it yourself, your choice is kept.

Your own settings win: Taurus only adds keys that are missing and never rewrites a value you chose. `/model` and `/advisor` inside Claude Code change the same file for new sessions. A `settings.json` that is not valid JSON is left untouched and reported as an error.

## The skills

| Skill | Use it to |
| --- | --- |
| `taurus` | Change settings, themes, wallpaper, language and app theming; point it at the right compositor guide. |
| `taurus-make-theme` | Create a color preset of your own, or tweak how Taurus recolors another app. |
| `taurus-diagnose` | Find out why the shell, a popup or a companion service is not working, reading logs before changing anything. |
| `taurus-develop` | Work on the shell's source code in a git checkout: widgets, launcher tabs, settings, translations, tests. |

## What the agent can see

Two commands give an agent the whole picture, and neither starts the shell:

- `taurus commands --json` lists every command with its usage and a risk level: `read`, `change` or `disruptive`.
- `taurus info paths --json` reports the install dir (and whether it is read-only), your settings, the shipped defaults, backups, state, logs and your own themes.

## Safety rules the skills follow

- **Configuration is files you own.** The agent edits your settings and themes, never the install dir, which an update overwrites.
- **Every write is backed up.** `taurus config` copies `settings.json` to `~/.local/state/taurus/backups/` first. Undo the last change with `taurus config restore latest`, see your changes with `taurus config diff`, and reset one key with `taurus config reset <key>`.
- **Disruptive commands need your approval:** restarting the shell, locking, suspending, rebooting, powering off.
- **No `sudo`, and no passwords.** Configuring the shell never needs root. For the rare command that does, such as installing a package, the agent uses `pkexec`, so your system shows its own authentication dialog and the agent never sees a password. It tells you what the command does first.
- **No changes to your compositor config** unless you ask.

## Not (yet) included

Launching an agent from the shell with a key, a launcher tab for prompts, and handing errors to an agent are not part of this first version.
