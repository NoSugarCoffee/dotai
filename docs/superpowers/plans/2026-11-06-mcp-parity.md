# MCP Server Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `bash scripts/install.sh` gives Claude Code, Codex, and Pi the same MCP servers, and every later drift is reported with a one-command fix.

**Architecture:** The private repo moves from `skills/internal/` to `internal/` and its `sync-mcp` grows four modes (sync, `--emit-pi`, `--check`, `--adopt`/`--except`) backed by small Ruby libraries: a manifest loader, live-config readers per CLI, and a pure drift classifier. `install.sh` migrates old checkouts, runs the sync on every install, feeds private servers into its existing Pi merge, and ends with a warn-only drift check.

**Tech Stack:** Bash (`scripts/install.sh`), Ruby 3.4 stdlib + minitest (`internal/scripts/`), Python 3 stdlib (Pi merge heredoc), APM 0.35+, `codex mcp list --json`.

**Spec:** `docs/superpowers/specs/2026-11-06-mcp-parity-design.md`

## Global Constraints

- No company server name or URL in this public repo — not in code, tests, docs, or this plan. Concrete names live only in the private repo (seed list: `internal/docs/plans/2026-11-06-mcp-parity-seed.md`).
- Published skill links stay `internal.<name>`; `~/.claude/skills/internal.cas-login/cas-login.sh` keeps working.
- Manifest entries accept exactly `name`, `registry: false`, `transport: http`, `url`; no headers or credentials.
- A remote plain-HTTP server is never installed to Codex (APM rejects it); this is a code rule, not an exceptions line.
- Exceptions file: one `<tool> <name>` per line, `tool` ∈ `claude`, `codex`, `pi`; `#` comments and blank lines allowed; anything else is an error.
- `install.sh` and `sync.sh` warn on drift and exit 0; `install.sh --check-mcp` exits 1 on any finding.
- Pi's `mcp.json` has exactly one writer: the `install.sh` Pi merge.
- Never auto-delete a dirty legacy `skills/internal/` checkout.
- Every script option is passed explicitly by `install.sh` (`--public-mcp`, `--claude-json`, `--pi-mcp`); `sync-mcp` has no path defaults besides its own manifest and exceptions file.
- MR/PR: squash and delete source branch.

**Plan decision beyond the spec (confirm in review):** the spec's goal "every declared server in all three CLIs" also covers *public* servers, which today reach Claude/Codex only at project scope. `sync-mcp` therefore installs public `.mcp.json` servers to Claude and Codex at user scope too (Task 3).

## Review Focus

1. Pi already holds a hand-made entry with the same name as a manifest server (with extra keys such as `timeout`): the merge must leave it untouched and the check must not report it as drift when the URL matches — test in Task 8.
2. `codex` is not on `PATH` or `codex mcp list --json` fails: `--check` must fail with a message naming Codex, not report every server missing — test in Task 4.
3. `~/.claude.json` or Pi `mcp.json` missing on a fresh machine: treated as "no servers", so everything is reported missing, not a crash — test in Task 4.
4. Legacy `skills/internal/` exists but is an empty directory (user never had access): removed without git checks — test in Task 7.
5. `--adopt-mcp` for a name present in two CLIs with different URLs: refused, naming both URLs — test in Task 5.

---

## Part 1 — private repo (`NoSugarCoffee/dotai-internal`)

Work in the current checkout `skills/internal/` on branch `feat/mcp-parity`. Run tests from that directory: `ruby tests/<file>_test.rb`.

### Task 1: New layout

**Files:**
- Move: `cas-login/`, `cursor-cookie-rotation/`, `gitlab-sentinel/` → `skills/`
- Move: `apm.yml` → `mcp/apm.yml`
- Create: `mcp/exceptions.conf` (header comment only for now)
- Modify: `scripts/sync-mcp` (manifest path `../mcp/apm.yml`), `tests/sync-mcp_test.rb` (setup copies to `mcp/apm.yml`), `README.md` (mount point `internal/`, layout, paths)
- Create: `docs/plans/2026-11-06-mcp-parity-seed.md` already exists from planning; keep it.

- [ ] **Step 1:** `git mv` the three skills and the manifest; create `mcp/exceptions.conf` with a comment describing the format from Global Constraints.
- [ ] **Step 2:** Update `sync-mcp` manifest path and the test setup path.
- [ ] **Step 3:** Run `ruby tests/sync-mcp_test.rb` — expected: all existing tests PASS.
- [ ] **Step 4:** Update README: mounted at `internal/`, layout tree from the spec §1, run commands as `./internal/scripts/sync-mcp`.
- [ ] **Step 5:** Commit `refactor: move skills and MCP manifest into skills/ and mcp/`.

### Task 2: Manifest library

**Files:**
- Create: `scripts/lib/mcp_manifest.rb`, `tests/mcp_manifest_test.rb`
- Modify: `scripts/sync-mcp` (use the library; remove its inline validation)

**Interfaces — Produces:**
- `McpServer = Data.define(:name, :url)` with `#plain_http_remote? -> bool` (scheme `http`, host not `localhost`/`127.0.0.1`/`::1`).
- `McpException = Data.define(:tool, :name)`.
- `TOOLS = %w[claude codex pi].freeze`
- `load_private_servers(path:) -> Array[McpServer]` — the existing validation rules moved verbatim (exact keys, unique names, name regex, http transport, no userinfo); raises `ManifestError` (< `StandardError`).
- `load_public_servers(path:) -> Array[McpServer]` — reads `{"mcpServers": {name: {"type":"http","url":…,"headers":{}}}}`; missing file → `[]`; non-http type or non-empty `headers` → `ManifestError` naming the server.
- `load_exceptions(path:) -> Array[McpException]` — missing file → `[]`; bad line → `ManifestError` with line number.
- `expected_servers(servers:, exceptions:, tool:) -> Hash[String, String | nil]` — name ⇒ url for every server except plain-HTTP remotes when `tool == 'codex'`, plus each exception for that tool mapped to `nil` (allowed, URL not compared).

- [ ] **Step 1: Failing tests** in `tests/mcp_manifest_test.rb`:
  `test_private_rejects_headers` (message includes `credentials are not supported`), `test_private_rejects_duplicate_names`, `test_public_missing_file_is_empty`, `test_public_rejects_nonempty_headers`, `test_exceptions_parses_comments_and_blanks`, `test_exceptions_rejects_unknown_tool` (message includes `line 2`), `test_expected_skips_plain_http_for_codex_only` (fixture `http://example.test/mcp` present for `claude`, absent for `codex`), `test_expected_includes_exceptions_as_nil`. Use `example.test` fixtures only.
- [ ] **Step 2:** `ruby tests/mcp_manifest_test.rb` — FAIL (cannot load file).
- [ ] **Step 3:** Implement `scripts/lib/mcp_manifest.rb`; switch `sync-mcp` to `require_relative 'lib/mcp_manifest'` and `load_private_servers`.
- [ ] **Step 4:** Run both test files — PASS.
- [ ] **Step 5:** Commit `refactor(sync-mcp): extract manifest loading into a library`.

### Task 3: Sync includes public servers; `--emit-pi`

**Files:** Modify `scripts/sync-mcp`, `tests/sync-mcp_test.rb`

**Interfaces:**
- Consumes: Task 2 loaders.
- Produces CLI:
  - `sync-mcp --public-mcp PATH [--dry-run] [--target claude,codex]` — installs public + private servers (public first) with the existing `apm install -g … --force` command shape and target-retention logic; `--public-mcp` is required.
  - `sync-mcp --emit-pi` — prints `{"mcpServers": {name: {"type": "http", "url": url}}}` for **private** servers only, pretty-printed JSON, exit 0; no APM calls.
  - A public and a private server with the same name → `ManifestError` before any install.
  - Retirement (spec "Retiring removed servers"): after installs, `sync-mcp` reads `~/.apm/.dotai-managed-mcp.json` (`{"synced": [names]}`; missing → `[]`); each recorded name absent from both manifests is removed from the `dependencies.mcp` list of `~/.apm/apm.yml`; if any were removed, it runs `apm install -g` once; then it writes the record as the current manifest names. `--dry-run` prints the retirements without writing.

- [ ] **Step 1: Failing tests:** `test_sync_installs_public_then_private` (fixture public file with one `https://example.test/pub` server → first logged call has `--mcp` of that name), `test_sync_requires_public_mcp`, `test_name_collision_public_private_fails_before_install`, `test_emit_pi_prints_private_only` (parse stdout; keys equal private names; each value `{"type"=>"http","url"=>…}`; `calls` empty), `test_sync_retires_recorded_server_dropped_from_manifest` (record lists `gone`, `~/.apm/apm.yml` fixture holds `gone` and `user-added`; after sync `gone` is removed, `user-added` kept, last logged call is `["install", "-g"]`), `test_sync_without_retirements_skips_reinstall`, `test_sync_writes_record`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement mode dispatch on `ARGV[0]` (`--emit-pi`, `--check`, `--adopt`, `--except`, else sync options); only sync and emit-pi in this task.
- [ ] **Step 4:** Run all tests — PASS; update existing tests to pass `--public-mcp` with an empty fixture.
- [ ] **Step 5:** Commit `feat(sync-mcp): sync public servers and emit private servers for Pi`.

### Task 4: Live readers and drift check

**Files:**
- Create: `scripts/lib/mcp_live.rb`, `scripts/lib/mcp_drift.rb`, `tests/mcp_drift_test.rb`
- Modify: `scripts/sync-mcp`, `tests/sync-mcp_test.rb`

**Interfaces — Produces:**
- `LiveServer = Data.define(:name, :url)` (`url` nil for stdio).
- Classes (integration boundaries), each `#servers -> Array[LiveServer]`:
  - `ClaudeLiveConfig.new(path:)` — `mcpServers` of `~/.claude.json`; missing file → `[]`.
  - `CodexLiveConfig.new(command: %w[codex mcp list --json])` — maps each item's `transport.url`; command missing or non-zero exit → raises `LiveConfigError` with "Codex" and the stderr.
  - `PiLiveConfig.new(path:)` — `mcpServers` of Pi `mcp.json`; missing file → `[]`.
- `Finding = Data.define(:tool, :kind, :name, :detail)`, `kind` ∈ `:missing`, `:undeclared`, `:url_mismatch`.
- `classify(expected:, live:) -> Array[Finding]` where `expected: Hash[tool ⇒ Hash[name ⇒ url|nil]]`, `live: Hash[tool ⇒ Array[LiveServer]]`. Pure. A `nil` expected URL (exception) never yields `:url_mismatch`; an exception absent from live is not `:missing`.
- `format_finding(finding) -> String` — one line including the fix: missing → `bash scripts/install.sh`; undeclared → `bash scripts/install.sh --adopt-mcp NAME` or `--except-mcp TOOL NAME`; url_mismatch → both URLs.
- CLI: `sync-mcp --check --public-mcp PATH --claude-json PATH --pi-mcp PATH` — prints findings, exit 1 if any, 0 with `MCP servers in sync` otherwise; `LiveConfigError` → exit 2 with its message.

- [ ] **Step 1: Failing tests** (`tests/mcp_drift_test.rb`, pure): `test_missing`, `test_undeclared`, `test_url_mismatch`, `test_exception_absent_is_not_missing`, `test_exception_url_not_compared`, `test_in_sync_is_empty`. In `tests/sync-mcp_test.rb` with a stub `codex` script on `PATH` (same pattern as the `apm` stub): `test_check_exit_1_and_prints_fix`, `test_check_missing_claude_json_reports_missing`, `test_check_codex_failure_names_codex` (stub exits 1; exit status 2; stderr includes `Codex`).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement the two libraries and the `--check` mode.
- [ ] **Step 4:** Run all tests — PASS.
- [ ] **Step 5:** Commit `feat(sync-mcp): report MCP drift across Claude, Codex, and Pi`.

### Task 5: Adopt and except

**Files:** Modify `scripts/sync-mcp`, `tests/sync-mcp_test.rb`

**Interfaces:**
- Consumes: Task 4 readers, Task 2 loaders.
- CLI:
  - `sync-mcp --adopt NAME --claude-json PATH --pi-mcp PATH` — finds `NAME` across the three readers; appends `{name, registry: false, transport: http, url}` to `mcp/apm.yml`; prints the added entry. Refuses (exit 1, manifest unchanged) when: not found; any instance has `url` nil (stdio); Claude/Pi entry has non-empty `headers`; URL has userinfo; instances disagree on URL (message lists each tool and URL); name already in a manifest.
  - `sync-mcp --except TOOL NAME --claude-json PATH --pi-mcp PATH` — appends `TOOL NAME` to `mcp/exceptions.conf`; refuses unknown tool, server not present in that tool, or duplicate line.
- Neither mode runs APM; `install.sh` re-runs the full install afterwards.

- [ ] **Step 1: Failing tests:** `test_adopt_appends_entry`, `test_adopt_refuses_stdio`, `test_adopt_refuses_headers`, `test_adopt_refuses_conflicting_urls` (stderr includes both URLs), `test_adopt_refuses_existing_name`, `test_except_appends_line`, `test_except_refuses_absent_server`. Every refusal test asserts the manifest/exceptions file bytes are unchanged.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement; write files via temp file + rename.
- [ ] **Step 4:** Run all tests — PASS.
- [ ] **Step 5:** Commit `feat(sync-mcp): adopt hand-added servers or record exceptions`.

### Task 6: Push the private branch

- [ ] **Step 1:** Update README sections for the new modes (one paragraph each, commands as run from dotai).
- [ ] **Step 2:** `ruby -e 'Dir["tests/*_test.rb"].each { |f| require_relative f }'` — all PASS.
- [ ] **Step 3:** Commit, push `feat/mcp-parity`, open the MR with squash + remove source branch. Seed data (adopted servers, exceptions) is added in Task 10 after the dotai wiring exists.

---

## Part 2 — dotai

Branch `feat/mcp-parity` in dotai. No bash test framework is installed; tests are plain bash scripts under `scripts/tests/` that exit non-zero on failure. To make functions testable, `install.sh` ends with `[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"`.

### Task 7: Move the submodule and migrate old checkouts

**Files:**
- Modify: `.gitmodules` (via `git mv skills/internal internal`), `scripts/install.sh`, `scripts/verify-skills-layout.sh`
- Create: `scripts/tests/migrate-internal_test.sh`

**Interfaces — Produces (in `install.sh`):**
- `INTERNAL_DIR="$ROOT/internal"`, `LEGACY_INTERNAL_DIR="$ROOT/skills/internal"`.
- `resolve_internal_skills` — emits `internal.<name>\t<dir>` for `internal/skills/*/SKILL.md`; called with the other resolvers in `--list` and the main path.
- `prune_managed_symlinks` also matches targets under `$INTERNAL_DIR`; `verify-skills-layout.sh` STALE check likewise.
- `migrate_legacy_internal_checkout` — returns 0 when there is no legacy dir; removes an empty legacy dir; for a git checkout requires all of: `git status --porcelain --untracked-files=all` empty, `git stash list` empty, `git branch -r --contains HEAD` non-empty; when clean removes `skills/internal/` and `.git/modules/skills/internal` and drops a leftover `submodule.skills/internal` config section if present; otherwise prints which checks failed plus the manual removal command and returns 1. Called first in `main` (before submodule init and skill resolution); a non-zero return stops `install.sh`.
- Submodule init becomes `git submodule update --init internal`.

- [ ] **Step 1: Failing test** `scripts/tests/migrate-internal_test.sh`: builds a scratch bare remote + clone with a nested repo at `skills/internal` and `ROOT` pointed at it, sources `install.sh`, and asserts: clean → dir and module dir gone, exit 0; untracked file → exit 1, dir kept, output names "untracked"; stash present → exit 1; unpushed commit → exit 1; empty dir → removed; no legacy dir → exit 0 and nothing printed.
- [ ] **Step 2:** `bash scripts/tests/migrate-internal_test.sh` — FAIL.
- [ ] **Step 3:** `git mv skills/internal internal`; implement the function, resolver, prune root, init path, `BASH_SOURCE` guard; update `verify-skills-layout.sh`.
- [ ] **Step 4:** Run the test — PASS. Run `bash scripts/install.sh --list | grep '^internal\.'` — expected: the same three `internal.*` names as before, sources under `internal/skills/`.
- [ ] **Step 5:** Commit `refactor(install): mount the private repo at internal/ and migrate old checkouts`.

### Task 8: Sync on every install, private servers to Pi, drift check

**Files:**
- Modify: `scripts/install.sh`
- Create: `scripts/tests/pi-merge_test.sh`

**Interfaces:**
- Consumes: `sync-mcp` modes from Tasks 3–5.
- `SYNC_MCP="$INTERNAL_DIR/scripts/sync-mcp"`; `internal_available` ⇔ `-x "$SYNC_MCP"`.
- `merge_public_mcp` renamed `merge_managed_mcp SRC DEST STATE`, behaviour unchanged; `install_pi` builds SRC as a temp file = public `.mcp.json` servers ∪ `sync-mcp --emit-pi` servers (when available); a name in both → error and `install_pi` returns 1.
- `run_private_sync` — when available runs `env -u CLAUDE_CONFIG_DIR "$SYNC_MCP" --public-mcp "$ROOT/.mcp.json"`; otherwise prints `→ Private MCP sync skipped (internal/ not initialised)`. Called in `main` before `install_pi`.
- `check_mcp` — runs `"$SYNC_MCP" --check --public-mcp "$ROOT/.mcp.json" --claude-json "$HOME/.claude.json" --pi-mcp "$PI_AGENT_DIR/mcp.json"`. Default run: called last, non-zero only warns. Flags:
  - `--check-mcp` → exit with `check_mcp`'s status.
  - `--adopt-mcp NAME` → `sync-mcp --adopt NAME …`, then the full install.
  - `--except-mcp TOOL NAME` → `sync-mcp --except TOOL NAME …`, then `check_mcp`.
  - `--sync-mcp` unchanged.
- `usage` lists all flags.

- [ ] **Step 1: Failing test** `scripts/tests/pi-merge_test.sh` (sources `install.sh`, temp dirs, stub `sync-mcp` printing a fixed `--emit-pi` JSON): private server written to Pi and recorded in the sidecar; existing same-name hand entry with `"timeout": 600` left byte-identical and not recorded; public/private name collision → non-zero, Pi file unchanged; private server removed from emit output → retired from Pi.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run both `scripts/tests/*.sh` — PASS. `bash scripts/install.sh --help` lists the four MCP flags.
- [ ] **Step 5:** Commit `feat(install): sync private MCP servers to every CLI and check for drift`.

### Task 9: Docs and agent instruction

**Files:** `README.md`, `AGENTS.md`, `global/.apm/instructions/agents.instructions.md`

- [ ] **Step 1:** `AGENTS.md`: layout tree (`internal/` with `skills/`, `mcp/`, `scripts/`), "Private" skill steps (`internal/skills/<name>/SKILL.md`, `git submodule update --init internal`), a short "MCP servers" section: manifests, exceptions, `--check-mcp`, `--adopt-mcp`, `--except-mcp`, and that deleting a manifest entry retires the server everywhere while hand-added servers are only reported.
- [ ] **Step 2:** `README.md`: same path updates (lines that mention `skills/internal`).
- [ ] **Step 3:** Instruction line under a new "MCP servers" heading: "To add an MCP server, declare it in `internal/mcp/apm.yml` (private) or `apm.yml` (public) and run `bash scripts/install.sh` in dotai; never run `claude mcp add`, `codex mcp add`, or `pi mcp add` directly."
- [ ] **Step 4:** `grep -rn 'skills/internal' --exclude-dir=apm_modules --exclude-dir=.git --exclude-dir=docs .` — expected: only the migration code in `install.sh` and its test.
- [ ] **Step 5:** Commit `docs: describe internal/ layout and MCP parity commands`.

### Task 10: Seed data and live acceptance

- [ ] **Step 1:** `bash scripts/install.sh` on this machine — expected: migration removes the old checkout (or stops with a reason to resolve), sync runs, warn-only drift lists the hand-added servers.
- [ ] **Step 2:** Apply the seed list in `internal/docs/plans/2026-11-06-mcp-parity-seed.md` with `--adopt-mcp` / `--except-mcp`.
- [ ] **Step 3:** `bash scripts/install.sh --check-mcp` — expected: `MCP servers in sync`, exit 0. `bash scripts/verify-skills-layout.sh` — expected: all checks pass.
- [ ] **Step 4:** Commit the seed changes in the private repo, push, update its MR.
- [ ] **Step 5:** In dotai, bump the `internal` pointer, push, open the PR (squash, delete branch) noting it depends on the private MR. After the private MR squash-merges, bump the pointer to the merged commit before merging the PR.
