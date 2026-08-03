# AGENTS.md

Instructions for AI agents operating on this repository (Codex, Claude Code, Copilot, Cursor, and similar tools that read a repo-root agent file).

## Repo purpose

`dotai` is a personal cross-tool AI configuration repo. It manages coding rules, reusable skills, agent definitions, and lifecycle hooks — and publishes them to each tool's expected location via `scripts/install.sh`.


## Repo layout

```
rules/          Authoritative rule text (edit here, then run install.sh)
  coding.md     Coding standards — style, errors, typing, dependencies

skills/         Reusable skill directories (symlinked into all tool dirs by install.sh)
  code-review/            Master review skill + nested reviewers (architecture-review, …)
    architecture-review/  Focused sub-skill (reachable under code-review/ after install)
    coding-standards-review/
    maintainability-review/
    performance-review/
    security-review/
  project-logo-author/
  project-readme-author/

agents/         Named sub-agent persona definitions
  architect.md  Focus: system boundaries, interfaces, tradeoffs, long-term maintainability
  reviewer.md   Focus: correctness, regressions, clarity, test gaps

hooks/          Lifecycle hooks loaded by compatible runtimes
  hooks.json            Hook registry (session_start, task_complete)
  on-session-start.md   Read rules, check for existing skills, confirm scope
  on-task-complete.md   Verify output, re-check assumptions, note follow-ups

clis.json       External CLIs the setup depends on (name → purpose, package, binary,
                install/version/check/update commands)

scripts/
  install.sh    Publishes rules and skills to ~/.claude, ~/.cursor, ~/.agents, ~/.copilot,
                then installs any CLI in clis.json that is missing
  skills.mjs    Adds, updates, and lists vendored skills (skills/skills.json)
  clis.mjs      Installs, checks, and updates the CLIs in clis.json
  sync.sh       (utility) syncs local state
```

## Vendored skill vs. CLI-managed tool

A skill whose upstream ships as a CLI that installs and updates its own skills does **not** belong in `skills/`. Vendoring it there gets the `{category}.{name}` prefix, which breaks the upstream's cross-skill slugs (`/hyperframes-core`) and hides the install from its own updater. Declare the CLI in `clis.json` instead and let it own its skill directories.

## Install targets

Run `bash scripts/install.sh` after editing any file under `rules/` or `skills/`.

| Target | What gets installed |
|--------|---------------------|
| `~/.claude/rules/coding.md` | Symlink → `rules/coding.md` |
| `~/.cursor/rules/coding.mdc` | Generated from `rules/coding.md` with Cursor frontmatter |
| `~/.cursor/skills/<name>` | Symlink per top-level directory under `skills/` (nested reviewers live only under `code-review/`). |
| `~/.agents/skills/<name>` | Same symlink rules as Cursor skills |
| `~/.copilot/skills/<name>` | Same as Cursor skills |
| `~/.config/github-copilot/intellij/global-copilot-instructions.md` | Symlink → `rules/coding.md` |

Each **`install.sh`** run first **removes symlinks** under those `skills` directories whose target resolves into **this repo’s `skills/`** tree, then recreates symlinks from the current checkout. Ordinary directories (e.g. unrelated skills) and symlinks pointing elsewhere are left alone.

## Adding a new skill

1. Create `skills/<skill-name>/SKILL.md` (and any supporting files). For a **focused code-review sub-skill**, add `skills/code-review/<skill-name>/SKILL.md`.
2. Run `bash scripts/install.sh` to symlink it into all tool directories.
3. No other code changes are needed.

## Adding or changing rules

1. Edit `rules/coding.md` (single source of truth).
2. Run `bash scripts/install.sh` to propagate the update.

