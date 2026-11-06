# MCP server parity across Claude Code, Codex, and Pi

Date: 2026-11-06
Status: draft, awaiting review

## Problem

dotai keeps rules, global instructions, and skills in sync across Claude Code,
Codex, and Pi. MCP servers drift: each CLI has a mostly different set, so a
skill that needs a given server works in one CLI and breaks in another.

Four causes, observed on the main machine:

1. The private sync (`skills/internal/scripts/sync-mcp`) targets only Claude
   and Codex. Pi receives only the public `.mcp.json`.
2. The private sync is opt-in (`install.sh --sync-mcp`); a plain `install.sh`
   never runs it.
3. Servers added by hand (`claude mcp add`, `codex mcp add`, `pi mcp add`,
   often by an agent following a request literally) are in no manifest.
4. The private submodule is mounted at `skills/internal/` although it also
   holds MCP manifests, scripts, and tests, so its layout hides where private
   configuration lives.

## Goals

- Every server declared in a manifest is present in all three CLIs, except
  where an exception or a transport rule says otherwise.
- One command (`bash scripts/install.sh`) brings all three CLIs into line.
- Hand-added servers are detected on every sync and are as cheap to declare as
  they were to add.
- Company server names and URLs stay out of this public repo.

## Non-goals

- Hooks, plugins/packages, Cursor, and Copilot.
- Removing servers that dotai never installed (hand-added ones are reported,
  not deleted).
- Private global instructions (the new layout leaves room; nothing is added).

## Design

### 1. Private repo moves to `internal/`

The `NoSugarCoffee/dotai-internal` submodule moves from `skills/internal/` to
`internal/` at the repo root, with a layout mirroring the public repo:

```
internal/
  skills/<name>/SKILL.md   private skills
  mcp/apm.yml              private MCP servers (was apm.yml at the root)
  mcp/exceptions.conf      servers allowed in one CLI only
  scripts/sync-mcp         sync, --emit-pi, --check, --adopt, --except
  tests/
```

`install.sh` resolves `internal/skills/*` as the `internal` category, so
published link names (`internal.<name>`) and paths such as
`~/.claude/skills/internal.cas-login/...` are unchanged. `prune_managed_symlinks`
treats `internal/` as a managed root alongside `skills/` and `apm_modules/`.

References updated: `.gitmodules`, `install.sh` (submodule init, `sync-mcp`
path), `README.md`, `AGENTS.md` (layout, "Private" skill steps), and the
private repo's README.

#### Migration of existing checkouts

Before resolving or pruning anything, `install.sh` checks for a leftover
`skills/internal/` from the old mount point. If present:

- **Clean** — no staged, modified, or untracked files; empty stash; and `HEAD`
  contained in at least one remote-tracking branch (no unpushed commits): it
  deinitialises the old submodule and removes `skills/internal/` and
  `.git/modules/skills/internal`, printing what it removed.
- **Not clean** — it stops before touching any link and prints which of the
  three conditions failed plus the manual command to remove it once the work
  is saved.

A fresh clone never has the old directory, so the check is a no-op there.

### 2. Sources of truth

| Scope | File | Notes |
|---|---|---|
| Public servers | `apm.yml` → `.mcp.json` | Unchanged |
| Private servers | `internal/mcp/apm.yml` | Only private source; `~/.apm/apm.yml` is APM's record of global installs and is never edited directly |
| Single-CLI servers | `internal/mcp/exceptions.conf` | One `<tool> <name>` per line, `tool` ∈ `claude`, `codex`, `pi`; `#` comments |

Transport rule kept in code, not in the exceptions file: a remote plain-HTTP
server is skipped for Codex, because APM rejects it there.

The initial exceptions file and the servers adopted into the private manifest
are decided in the private repo MR (decided in review: three hand-added
code-graph servers are adopted; Codex built-ins, one Codex stdio server, one
Claude HTTP server, and one Pi stdio server become exceptions).

### 3. Writing servers — one writer per config file

| CLI | Writer | Mechanism |
|---|---|---|
| Claude | `sync-mcp` | `apm install -g --target claude --mcp ...` (unchanged) |
| Codex | `sync-mcp` | `apm install -g --target codex --mcp ...` (unchanged) |
| Pi | `install.sh` Pi merge | Merges public `.mcp.json` **and** `sync-mcp --emit-pi` output |

`sync-mcp --emit-pi` prints the private servers as `{"mcpServers": {...}}` in
Pi's shape. The existing managed merge (`.dotai-managed-mcp.json`) records
both public and private entries, so it keeps retiring servers removed from
either manifest and keeps user-added Pi entries.

A plain `install.sh` runs the private sync when `internal/` is initialised and
skips it, with one informational line, when the submodule is unavailable (no
access). `--sync-mcp` remains as a standalone entry point.

### 4. Drift check

`sync-mcp --check` reads each CLI's live server list:

- Claude: `~/.claude.json` → `mcpServers` (user scope)
- Codex: `codex mcp list --json`
- Pi: `$PI_CODING_AGENT_DIR/mcp.json` (default `~/.pi/agent/mcp.json`)

It compares those with the expected set (public + private manifests, minus
transport-rule skips, plus exceptions) and reports per CLI:

| Finding | Meaning | Printed fix |
|---|---|---|
| missing | declared, absent from the CLI | `bash scripts/install.sh` |
| undeclared | present, in no manifest and no exception | `install.sh --adopt-mcp <name>` or `install.sh --except-mcp <tool> <name>` |
| url-mismatch | same name, different URL | which side differs; edit the manifest or re-run install |

Exit status: `install.sh --check-mcp` exits 1 on any finding. `install.sh` and
`scripts/sync.sh` run the check as their last step and only warn (exit 0), so a
stray server never blocks an unrelated skill update.

### 5. Adoption

- `install.sh --adopt-mcp <name>` locates the server in whichever CLI has it,
  appends a `{name, registry: false, transport: http, url}` entry to
  `internal/mcp/apm.yml`, and runs the sync. It refuses, naming the reason,
  if the server is stdio, carries headers or tokens, has an embedded
  credential in the URL, or exists in two CLIs with different URLs.
- `install.sh --except-mcp <tool> <name>` appends the line to
  `internal/mcp/exceptions.conf`; it refuses a server that is not present in
  that CLI.

Both edit the private repo's working tree; committing and opening its MR
stays manual.

### 6. Agent instruction

One line in `global/.apm/instructions/agents.instructions.md`: to add an MCP
server, declare it in `internal/mcp/apm.yml` (private) or `apm.yml` (public)
and run `bash scripts/install.sh`; never use `claude mcp add`, `codex mcp add`,
or `pi mcp add` directly.

### Retiring removed servers

APM removes a server it owns from Claude and Codex once the entry leaves
`~/.apm/apm.yml` and `apm install -g` runs (verified with APM 0.35.0: "Removed
stale MCP server"). `sync-mcp` only ever adds to that file, so it records the
names it synced in `~/.apm/.dotai-managed-mcp.json`; on each sync, a recorded
name no longer in any manifest is removed from `~/.apm/apm.yml`, then
`apm install -g` runs once. Servers added with `claude mcp add` /
`codex mcp add` are never recorded and APM does not own them, so they are left
alone and the check reports them. Pi retires through its own managed merge.

## Known limits

- The check sees only user-scope Claude servers, not project-scope `.mcp.json`
  or claude.ai connectors.

## Testing

- `internal/tests/sync-mcp_test.rb`: check classification (missing,
  undeclared, url-mismatch, exceptions, HTTP-to-Codex rule); `--emit-pi`
  output shape; adopt and except edits and refusals.
- `install.sh` migration: a scratch repo with a clean leftover
  `skills/internal/` is removed; dirty, stashed, and unpushed variants each
  stop with the matching message and leave links untouched.
- `scripts/verify-skills-layout.sh` passes with the new `internal/skills/`
  source and unchanged `internal.*` link names.
- Live acceptance on the main machine: `install.sh` then
  `install.sh --check-mcp` exits 0.

## Delivery

1. Private repo MR (squash, delete source branch): `skills/` and `mcp/`
   layout, `sync-mcp` `--emit-pi`/`--check`/adopt/except, exceptions file,
   manifest additions, tests.
2. dotai PR (squash, delete branch): submodule move and pointer bump,
   migration, `install.sh` wiring and `--check-mcp`/`--adopt-mcp`/
   `--except-mcp`, docs, agent instruction.
