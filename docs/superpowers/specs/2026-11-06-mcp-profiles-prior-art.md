# Prior art: switching MCP servers between a public and a work context

Date: 2026-11-06
Status: research brief, direction not chosen
Builds on: `2026-11-06-mcp-parity-design.md`

## 1. Question

- **Feature**: choose which MCP servers (later perhaps skills and instructions)
  Claude Code, Codex, and Pi see, per context: *public* (github.com work, no
  company servers) or *work* (company servers included).
- **Our constraints**: one macOS machine; dotai publishes at user scope; three
  CLIs with different config homes; company server definitions must stay out
  of public repos; nearly all company servers are remote HTTP with OAuth.
- **Decision**: how a context is selected — a global toggle that rewrites user
  config, a per-session/per-directory selection, or a proxy that filters.

## 2. What we already have

- MCP parity design (approach A): public manifest `apm.yml` + private
  `internal/mcp/apm.yml`, per-CLI writers, drift check. A machine without the
  private submodule already gets public servers only.
- dotnix `apps/claude-code/claude-profile.sh` (`ae1bc7f`): `claude-profile NAME`
  runs Claude under `~/.claude-profiles/NAME` via `CLAUDE_CONFIG_DIR`, symlinks
  everything else to `~/.claude`, and **syncs `mcpServers` across profiles**
  (lines 7-9, `sync_json` `SHARED_KEYS = ("mcpServers", "projects")`). It
  separates *accounts*, and deliberately not tool sets: the `personal` profile
  has the same company servers as `work`.
- `install.sh` already unsets `CLAUDE_CONFIG_DIR` around APM calls
  (`scripts/install.sh:274-275,483`) so global installs land in the shared
  `~/.claude.json`.

**Extension point**: the manifest layer of the parity design. A context is a
choice of which manifest layers apply to which CLI target.

## 3. How others do it

### Native CLI mechanisms (Claude Code 2.1.318, codex-cli 0.166.0, pi 1.5.0; tested with throwaway homes)

| Mechanism | Claude Code | Codex | Pi |
|---|---|---|---|
| Directory-scoped file | `.mcp.json`, also found in **parent** dirs; per-server approval | `.codex/config.toml`, git root → cwd, trusted projects only; parent trust does not cover child repos | `.pi/mcp.json` in **cwd only**; can set `enabled: false` on a user server |
| Profile / flag | `--mcp-config` + `--strict-mcp-config` | `-p NAME` layers `$CODEX_HOME/NAME.config.toml`; can add or disable servers (`[profiles.x]` tables no longer read since 0.134) | `--no-mcp`, `--exclude-tools 'mcp__x__*'`; no config-file flag |
| Separate home | `CLAUDE_CONFIG_DIR` (moves `.claude.json` + `mcpServers`) | `CODEX_HOME` (also auth, history, sessions) | `PI_CODING_AGENT_DIR` (also auth, sessions, trust) |
| `includeIf "gitdir:"`-style selection | no | no | no |

Caveat: no CLI can disable a user-scope server from a committed file in Claude;
separate homes split auth and history unless shared by symlink.

### mcpm.sh (`0119b7f`, 2026-10-08, MIT)

Profile = tag on servers (`core/schema.py:8`). The client config gets one stdio
entry that runs a FastMCP proxy aggregating the profile
(`commands/client.py:629-630`, `fastmcp_integration/proxy.py:113`). Supports
Claude Code and Codex at user scope, not Pi. Remote servers pass `url` +
`headers` only — **no OAuth** (`proxy.py:91-97`). **Removal**: v2.0.0 dropped
the v1 router daemon and separate profile configs; profiles became tags, citing
"no daemon dependencies" and "eliminates router complexity"
(`CHANGELOG.md:160-176`, `MIGRATION_GUIDE.md:9-17`).

### 1mcp-app/agent (`08ab170`, 2026-11-05, Apache-2.0)

A long-running gateway; the subset is chosen per connection by `?preset=` or a
tag filter (`transport/http/middlewares/tagsExtractor.ts:10-30`), or per
directory via `.1mcprc` (`config/projectConfigTypes.ts:4,29-31`). Presets are
Mongo-style tag queries (`domains/preset/types/presetTypes.ts:15-30`). The only
option with OAuth: the gateway is an OAuth 2.1 server and holds upstream
authorisations. **Removal**: `--tags` deprecated for presets/tag-filter
(`CHANGELOG.md:760`).

### rulesync (`bbed9a8`, 2026-11-06, MIT)

No runtime layer: regenerates each CLI's config, including at user scope for
Claude, Codex, **and Pi** (`claudecode-mcp.ts:50-55`, `codexcli-mcp.ts:900-905`,
`pi-mcp.ts:173-181`). Contexts are layered source roots,
`inputRoots: ["./.rulesync", "./.rulesync.local"]`, later wins, merged by
server name (`docs/guide/separate-input-root.md:43-72`). OAuth stays native in
each client. **Removals**: per-server `targets` deprecated for per-tool blocks;
singular `--input-root` deprecated.

### ruler (`5e551e6`, 2026-10-27, MIT)

Rewrites project-scope files from a chosen `ruler.toml`
(`src/paths/mcp.ts:79-83`); no user scope, no Pi MCP. No profile concept.

## 4. Mapping

| Their decision | Why | Our equivalent | Verdict | Reason |
|---|---|---|---|---|
| rulesync layered roots, later wins | Optional private overlay over a shared base | public `apm.yml` + `internal/mcp/apm.yml` | **Adopt** | Already our shape; a context is "with or without the internal layer" |
| rulesync regenerates per-client config | No daemon, OAuth stays native | parity design writers | **Adopt** | Same writers; add a layer filter |
| Codex `-p NAME` layer file | Per-invocation override without a second home | none | **Adapt** | Cheap per-session switch for Codex only; needs an alias |
| Claude parent-dir `.mcp.json` | Directory-scoped servers | none | **Adapt** | Works for Claude only; Codex and Pi have no parent-dir equivalent |
| Separate config homes | Full isolation | `claude-profile` for Claude | **Adapt** | Only uniform per-session mechanism, but splits auth/history; needs symlink sharing per CLI |
| mcpm stdio proxy per profile | One-entry switching | none | **Reject** | Drops OAuth; our company servers are OAuth HTTP |
| mcpm v1 router daemon (removed) | — | — | **Reject** | Maintainers removed it for complexity |
| 1mcp gateway + presets | Per-connection filtering with OAuth | none | **Reject for now** | A daemon holding every credential is heavy for two contexts; keep `.1mcprc` per-directory idea |

## 5. Recommendation

The choice depends on how the two contexts mix on this machine:

1. **Contexts on different machines** — already solved by the parity design:
   no private submodule, public servers only. No new work.
2. **Same machine, one context at a time** — rulesync-style overlay:
   `install.sh --context public|work`, stored in a gitignored local file;
   `public` skips the internal layer for every CLI, and the drift check treats
   internal servers as undeclared-but-expected-absent. Smallest viable piece;
   switching rewrites user config, so it affects running sessions on restart.
3. **Same machine, both contexts concurrently** — per-session selection:
   Claude via `claude-profile` homes (dotnix stops syncing `mcpServers`, dotai
   writes per home), Codex via `-p work` layer file, Pi via a second
   `PI_CODING_AGENT_DIR` home with shared symlinks. Largest; touches dotnix.

Phased order: ship the parity design; then (2) as a flag; move to (3) only if
the global switch proves too coarse in practice.

### Decision (2026-11-06)

Neither account nor session is a context boundary: one Claude account serves
both contexts, and one session can touch both. Every selection mechanism above
keys on machine, account, or session, so none fits. Context switching is not
built. Instead:

1. Ship the parity design: all servers in every CLI is the right default for
   mixed sessions; machines without the private submodule stay public-only.
2. Reduce the idle cost rather than hide servers: Claude Code already defers
   MCP tool schemas until searched; verify Codex's and Pi's equivalents (Pi's
   per-server exposure setting) and, where idle servers bloat context, have
   the writer set lazy exposure for internal servers.
3. Revisit switching only on evidence: measured context cost or an internal
   server misused in public work.

## 6. Not verified

- Whether a Claude `.mcp.json` entry accepts `enabled: false`.
- Pi behaviour with two `PI_CODING_AGENT_DIR` homes sharing skills and
  extensions by symlink.
- Codex OAuth tokens when the same server appears only under `-p work`.
- Token/context cost of carrying internal servers in public sessions (the
  motivating cost) was not measured.
