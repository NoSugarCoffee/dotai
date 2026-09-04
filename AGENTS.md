# AGENTS.md

Instructions for AI agents operating on this repository (Codex, Claude Code, Copilot, Cursor, and similar tools that read a repo-root agent file).

## Repo purpose

`dotai` is a personal cross-tool AI configuration repo. It manages coding rules, reusable skills, agent definitions, and lifecycle hooks — and publishes them to each tool's expected location via `scripts/install.sh`.

Dependencies (upstream skills, MCP servers) are managed by [APM](https://github.com/microsoft/apm) through `apm.yml`. APM fetches and pins; `install.sh` publishes. Neither does the other's job.

## Repo layout

```
rules/          Authoritative rule text (edit here, then run install.sh)
  coding.md     Coding standards — style, errors, typing, dependencies

skills/         Skills authored in this repo, by category
  <category>/<name>/SKILL.md
  code/code-review/       Master review skill + nested focused reviewers
  compass/                Symlinks into another repo (see external-skills.conf)

apm.yml         Upstream skill + MCP server dependencies
apm.lock.yaml   Resolved commits and per-file hashes (committed)
.mcp.json       Project MCP servers, regenerated from apm.yml by apm install
apm_modules/    Fetched upstream repos (gitignored; rebuilt by apm install)
vendored-skills.conf  Category for each apm_modules/ skill, matched on SKILL.md `name:`
external-skills.conf  Machine-local: skill dirs owned by another repo (gitignored)

agents/         Named sub-agent persona definitions
  architect.md  Focus: system boundaries, interfaces, tradeoffs, long-term maintainability
  reviewer.md   Focus: correctness, regressions, clarity, test gaps

hooks/          Lifecycle hooks loaded by compatible runtimes
  hooks.json            Hook registry (session_start, task_complete)
  on-session-start.md   Read rules, check for existing skills, confirm scope
  on-task-complete.md   Verify output, re-check assumptions, note follow-ups

scripts/
  install.sh               Publishes rules and skills to ~/.claude, ~/.cursor, ~/.agents, ~/.copilot
  sync.sh                  git pull + apm install + install.sh
  verify-skills-layout.sh  Asserts the published layout matches install.sh --list
  claude-tabs.sh           Saves and restores open Claude Code sessions as zellij tabs
```

## Install targets

Run `bash scripts/install.sh` after editing any file under `rules/` or `skills/`, or after `apm install`.

| Target | What gets installed |
|--------|---------------------|
| `~/.claude/rules/coding.md` | Symlink → `rules/coding.md` |
| `~/.cursor/rules/coding.mdc` | Generated from `rules/coding.md` with Cursor frontmatter |
| `~/.claude/skills/<category>.<name>` | Symlink per resolved skill |
| `~/.cursor/skills/<category>.<name>` | Same |
| `~/.agents/skills/<category>.<name>` | Same |
| `~/.copilot/skills/<category>.<name>` | Same |
| `~/.config/github-copilot/intellij/global-copilot-instructions.md` | Symlink → `rules/coding.md` |
| `~/.local/bin/claude-tabs` | Symlink → `scripts/claude-tabs.sh` |

Each **`install.sh`** run first **removes symlinks** under those `skills` directories that point into this repo's `skills/` or `apm_modules/`, then recreates them from the current checkout. Ordinary directories and symlinks pointing elsewhere are left alone.

`install.sh --list` prints the resolved `<link-name>` → `<source-dir>` pairs without touching anything.

## Adding a new skill

**Authored here:** create `skills/<category>/<name>/SKILL.md` and run `bash scripts/install.sh`. A directory without `SKILL.md` is skipped, not published.

**From an upstream repo:**

1. `apm install <owner>/<repo>#<sha> --skill <name>` — pins it in `apm.yml` and `apm.lock.yaml`.
2. Add `<name> <category>` to `vendored-skills.conf`.
3. `bash scripts/install.sh`.

Skills in `apm_modules/` are matched by the `name:` field of their SKILL.md frontmatter, not by directory name. `install.sh` fails if a declared name is missing or matches more than one skill.

Repos with no skill manifest reject `--skill`; install the whole repo and let `vendored-skills.conf` select what is published.

## Adding or changing rules

1. Edit `rules/coding.md` (single source of truth).
2. Run `bash scripts/install.sh` to propagate the update.

