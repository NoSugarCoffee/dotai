# AGENTS.md

Instructions for AI agents operating on this repository (Codex, Claude Code, Copilot, Cursor, and similar tools that read a repo-root agent file).

## Repo purpose

`dotai` is a personal cross-tool AI configuration repo. It manages coding rules, reusable skills, agent definitions, and lifecycle hooks — and publishes them to each tool's expected location via `scripts/install.sh`.


## Repo layout

```
rules/          Authoritative rule text (edit here, then run install.sh)
  coding.md     Coding standards — style, errors, typing, dependencies

skills/         Reusable skill directories (symlinked into all tool dirs by install.sh)
  architecture-review/
  code-review/
  maintainability-review/
  performance-review/
  security-review/

agents/         Named sub-agent persona definitions
  architect.md  Focus: system boundaries, interfaces, tradeoffs, long-term maintainability
  reviewer.md   Focus: correctness, regressions, clarity, test gaps

hooks/          Lifecycle hooks loaded by compatible runtimes
  hooks.json            Hook registry (session_start, task_complete)
  on-session-start.md   Read rules, check for existing skills, confirm scope
  on-task-complete.md   Verify output, re-check assumptions, note follow-ups

scripts/
  install.sh    Publishes rules and skills to ~/.claude, ~/.cursor, ~/.agents, ~/.copilot
  sync.sh       (utility) syncs local state
```

## Install targets

Run `bash scripts/install.sh` after editing any file under `rules/` or `skills/`.

| Target | What gets installed |
|--------|---------------------|
| `~/.claude/rules/coding.md` | Symlink → `rules/coding.md` |
| `~/.cursor/rules/coding.md` | Symlink → `rules/coding.md` |
| `~/.cursor/skills/<name>` | Symlink per skill directory |
| `~/.agents/skills/<name>` | Symlink per skill directory |
| `~/.copilot/skills/<name>` | Symlink per skill directory |

## Adding a new skill

1. Create `skills/<skill-name>/SKILL.md` (and any supporting files).
2. Run `bash scripts/install.sh` to symlink it into all tool directories.
3. No other code changes are needed.

## Adding or changing rules

1. Edit `rules/coding.md` (single source of truth).
2. Run `bash scripts/install.sh` to propagate the update.

