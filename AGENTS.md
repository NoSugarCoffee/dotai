# AGENTS.md

Instructions for AI agents operating on this repository (Codex, Claude Code, Copilot, Cursor, and similar tools that read a repo-root agent file).

## Repo purpose

`dotai` is a personal cross-tool AI configuration repo. It manages coding rules, reusable skills, agent definitions, and lifecycle hooks — and publishes them to each tool's expected location via `scripts/install.sh`.

Dependencies (upstream skills, MCP servers) are managed by [APM](https://github.com/microsoft/apm) through `apm.yml`. APM fetches and pins; `install.sh` publishes. Neither does the other's job.

## Boundary with dotnix

[dotnix](https://github.com/NoSugarCoffee/dotnix) installs programs and their settings, plus
anything that ships with a program, such as the skill pack a package bundles (`cua-driver`,
`ego-browser`): it links those so they move with the installed version. This repo owns what
agents are told: rules, global instructions, authored and vendored skills, hooks and MCP server
lists. Don't vendor a skill here that its program already ships, and don't install programs.

Private company MCP servers belong in the private submodule's
`internal/mcp/apm.yml`. Never add them to this repository's `apm.yml`,
`.mcp.json`, or lockfile.

## Repo layout

```
rules/          Authoritative rule text (edit here, then run install.sh)
  coding.md     Coding standards — style, errors, typing, dependencies

global/         APM package of user-scope agent instructions (MRs/PRs, …)
  .apm/instructions/*.instructions.md   No applyTo: compiled into every tool's global file

skills/         Skills authored in this repo, by category
  <category>/<name>/SKILL.md
  code/deprecated-code-review/  Deprecated: use code/dotai-review
  code/prior-art/         Research existing projects before designing a feature
  compass/                Symlinks into another repo (see external-skills.conf)

internal/       Private submodule (NoSugarCoffee/dotai-internal); empty without access
  skills/<name>/SKILL.md  Private skills, published as internal.<name>
  mcp/apm.yml             Private MCP servers
  mcp/exceptions.conf     MCP servers allowed in one CLI only
  scripts/sync-mcp        Installs MCP servers, checks drift, adopts hand-added ones

apm.yml         Upstream skills + public MCP server dependencies
apm.lock.yaml   Resolved commits and per-file hashes (committed)
.mcp.json       Public project MCP servers, regenerated from apm.yml by apm install
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
| `~/.claude/rules/`, `~/.codex/AGENTS.md`, `~/.cursor/AGENTS.md`, `~/.copilot/AGENTS.md`, `~/.gemini/GEMINI.md`, … | `apm install -g --only apm global/` + `apm compile -g` |
| `~/.pi/agent/AGENTS.md` | Generated: `global/` compiled with `apm compile --root <staging> --target agents`, then `rules/coding.md` appended — APM has no `pi` target, so `apm compile -g` skips it. `PI_CODING_AGENT_DIR` moves the directory |
| `$PI_CODING_AGENT_DIR/mcp.json` (default `~/.pi/agent/mcp.json`) | Merged copy of `.mcp.json`: managed entries are added and refreshed, entries you add or edit are kept (a copy, not a symlink — `pi mcp add` writes this file). `.dotai-managed-mcp.json` beside it records what was written |

Each **`install.sh`** run first **removes symlinks** under those `skills` directories that point into this repo's `skills/` or `apm_modules/`, then recreates them from the current checkout. Ordinary directories and symlinks pointing elsewhere are left alone.

`install.sh --list` prints the resolved `<link-name>` → `<source-dir>` pairs without touching anything.

## Adding a new skill

**Authored here:** create `skills/<category>/<name>/SKILL.md` and run `bash scripts/install.sh`. A directory without `SKILL.md` is skipped, not published.

**Private (company-internal):** commit `skills/<name>/SKILL.md` to the `internal/` submodule, then bump the submodule pointer here. Fetch it with `git submodule update --init internal`; without access the directory stays empty and nothing is published.

## MCP servers

Every server declared in `apm.yml` (public) or `internal/mcp/apm.yml` (private) goes to Claude Code, Codex, and Pi at user scope; `bash scripts/install.sh` installs them and ends with a drift check that only warns.

- `install.sh --check-mcp` reports servers missing from a CLI, servers no manifest declares, and URL mismatches; exits 1 on drift.
- `install.sh --adopt-mcp NAME` moves a hand-added HTTP server into `internal/mcp/apm.yml` and installs it everywhere.
- `install.sh --except-mcp TOOL NAME` allows a server in one CLI only (`internal/mcp/exceptions.conf`).
- A remote plain-HTTP server is never installed to Codex (APM rejects it).
- Deleting a manifest entry removes the server from all three CLIs. Servers dotai never installed are only reported, never deleted.
- The private repo used to live at `skills/internal/`; `install.sh` removes that leftover checkout when it is clean and pushed, and stops with the reason otherwise.

**From an upstream repo:**

1. `apm install <owner>/<repo>#<sha> --skill <name>` — pins it in `apm.yml` and `apm.lock.yaml`.
2. Add `<name> <category>` to `vendored-skills.conf`.
3. `bash scripts/install.sh`.

Skills in `apm_modules/` are matched by the `name:` field of their SKILL.md frontmatter, not by directory name. `install.sh` fails if a declared name is missing or matches more than one skill.

Repos with no skill manifest reject `--skill`; install the whole repo and let `vendored-skills.conf` select what is published.

## Adding or changing rules

1. Edit `rules/coding.md` for coding standards, or `global/.apm/instructions/` for agent workflow rules. Leave `applyTo` out of the latter: APM compiles only `applyTo`-less instructions into user-scope files.
2. Run `bash scripts/install.sh` to propagate the update.

