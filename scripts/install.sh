#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# dotai install.sh
# Publishes skills and rules into every local AI agent directory using
# SYMLINKS, so edits are reflected immediately.
#
# Skills are published as {category}.{name} from two sources:
#   skills/<category>/<name>/   authored here, or symlinked from another repo
#   apm_modules/                fetched and pinned by APM (see apm.yml)
#
# Usage: install.sh [--list | --sync-mcp [--dry-run] [--target claude,codex]]
#   --list   print the resolved "<link-name>\t<source-dir>" pairs and exit,
#            without touching any tool directory
#   --sync-mcp   delegate to the private MCP sync script without publishing skills
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"
SKILLS_SRC="$ROOT/skills"
APM_MODULES="$ROOT/apm_modules"
# Private submodule (NoSugarCoffee/dotai-internal): skills/, mcp/, scripts/.
INTERNAL_DIR="$ROOT/internal"
SYNC_MCP="$INTERNAL_DIR/scripts/sync-mcp"
RULES_SRC="$ROOT/rules"
GLOBAL_PKG="$ROOT/global"

BIN_DIR="$HOME/.local/bin"

# Category assignment for the upstream skills APM fetches into apm_modules/.
VENDORED_SKILLS_CONF="$ROOT/vendored-skills.conf"

# Gitignored, machine-local: maps a skill category to a directory of skills
# maintained in another repo. Format per line: "<category> <absolute-dir>".
EXTERNAL_SKILLS_CONF="$ROOT/external-skills.conf"

CLAUDE_DIR="$HOME/.claude"
CURSOR_DIR="$HOME/.cursor"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
CURSOR_SKILLS_DIR="$HOME/.cursor/skills"
COPILOT_SKILLS_DIR="$HOME/.copilot/skills"
COPILOT_INTELLIJ_DIR="$HOME/.config/github-copilot/intellij"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
# Pi keeps its user-scope context in a single agent directory, which
# PI_CODING_AGENT_DIR relocates; honour that instead of hardcoding the default.
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

# Tab-separated "<link-name>\t<source-dir>" for every skill to publish,
# resolved once in main() and consumed by link_skills for each tool.
LINKS_FILE=""

# ── Skill resolution ───────────────────────────────────────────────

# Print the `name:` field of a SKILL.md YAML frontmatter block.
skill_frontmatter_name() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1  && $0 == "---" { exit }
    NR > 1  && /^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }
  ' "$1" | tr -d '\r\042\047'
}

# Emit link pairs for skills living under skills/<category>/<name>/.
resolve_local_skills() {
  shopt -s nullglob
  local category_dir category skill_dir
  for category_dir in "$SKILLS_SRC"/*/; do
    category="$(basename "$category_dir")"
    for skill_dir in "$category_dir"*/; do
      # A directory without SKILL.md is not a skill; publishing it would put a
      # dead entry in every tool's skill list.
      [[ -f "$skill_dir/SKILL.md" ]] || continue
      printf '%s\t%s\n' "${category}.$(basename "$skill_dir")" "${skill_dir%/}"
    done
  done
}

# Emit link pairs for the private skills under internal/skills/<name>/, which
# keep the internal.<name> link names they had under skills/internal/.
resolve_internal_skills() {
  shopt -s nullglob
  local skill_dir
  for skill_dir in "$INTERNAL_DIR"/skills/*/; do
    [[ -f "$skill_dir/SKILL.md" ]] || continue
    printf '%s\t%s\n' "internal.$(basename "$skill_dir")" "${skill_dir%/}"
  done
}

# Emit link pairs for the apm_modules/ skills named in VENDORED_SKILLS_CONF.
resolve_vendored_skills() {
  [[ -f "$VENDORED_SKILLS_CONF" ]] || return 0
  if [[ ! -d "$APM_MODULES" ]]; then
    echo "  ! apm_modules/ is missing — run 'apm install' first" >&2
    return 1
  fi

  local index skill_md name
  index="$(mktemp)"
  # Packages ship generated per-tool copies of their skills in hidden
  # directories (.apm/, .claude/, .cursor/, .gemini/, … — impeccable alone has
  # 17). Indexing those would make every skill ambiguous, so hidden directories
  # are skipped and only the package's real source tree is scanned.
  while IFS= read -r -d '' skill_md; do
    name="$(skill_frontmatter_name "$skill_md")"
    [[ -n "$name" ]] || continue
    printf '%s\t%s\n' "$name" "$(dirname "$skill_md")" >> "$index"
  done < <(find "$APM_MODULES" \
    \( -name '.*' -o -name node_modules \) -prune \
    -o -name SKILL.md -type f -print0)

  local skill category link_name matches count status=0
  while read -r skill category; do
    [[ -z "$skill" || "$skill" == \#* ]] && continue
    # A category of "-" publishes the skill under its bare name, for skills
    # whose upstream tooling expects to find them by that exact name.
    if [[ "$category" == "-" ]]; then
      link_name="$skill"
    else
      link_name="${category}.${skill}"
    fi
    matches="$(awk -F'\t' -v n="$skill" '$1 == n { print $2 }' "$index")"
    count="$(printf '%s' "$matches" | grep -c . || true)"
    if [[ "$count" -eq 0 ]]; then
      echo "  ! ${link_name}: no SKILL.md in apm_modules/ declares this name — is it pinned in apm.yml?" >&2
      status=1
    elif [[ "$count" -gt 1 ]]; then
      echo "  ! ${link_name}: ambiguous, $count skills declare this name:" >&2
      printf '      %s\n' $matches >&2
      status=1
    else
      printf '%s\t%s\n' "$link_name" "$matches"
    fi
  done < "$VENDORED_SKILLS_CONF"

  rm -f "$index"
  return "$status"
}

# Reject two sources claiming the same {category}.{name}, which would other-
# wise resolve to whichever happened to be linked last.
assert_unique_link_names() {
  local dupes
  dupes="$(cut -f1 "$LINKS_FILE" | sort | uniq -d)"
  [[ -z "$dupes" ]] && return 0
  echo "  ! duplicate skill names:" >&2
  local name
  while read -r name; do
    printf '      %s\n' "$name" >&2
    awk -F'\t' -v n="$name" '$1 == n { print "        ← " $2 }' "$LINKS_FILE" >&2
  done <<< "$dupes"
  return 1
}

# ── Publishing helpers ─────────────────────────────────────────────

# Remove every symlink in target_dir that this repo owns, so renamed and
# removed skills do not linger. Ordinary directories and symlinks pointing
# outside the repo are left alone.
#
# Compares the raw link target as well as the resolved path: skills/compass/*
# are themselves symlinks into another repo, so resolving fully would miss them.
prune_managed_symlinks() {
  local target_dir="$1"
  shopt -s nullglob
  local entry raw resolved root
  for entry in "${target_dir}"/*; do
    [[ -L "$entry" ]] || continue
    raw="$(readlink "$entry" 2>/dev/null || true)"
    [[ -z "$raw" ]] && continue
    resolved="$(realpath "$entry" 2>/dev/null || readlink -f "$entry" 2>/dev/null || echo "$raw")"
    for root in "$SKILLS_SRC" "$APM_MODULES" "$INTERNAL_DIR"; do
      if [[ "$raw" == "$root"/* || "$resolved" == "$root"/* ]]; then
        rm -f "${entry:?}"
        echo "  ✓ prune $(basename "$entry")"
        break
      fi
    done
  done
}

# Symlink every resolved skill into target_dir under its {category}.{name}.
link_skills() {
  local target_dir="$1"
  mkdir -p "$target_dir"
  prune_managed_symlinks "$target_dir"

  local link_name source_dir
  while IFS=$'\t' read -r link_name source_dir; do
    rm -rf "${target_dir:?}/$link_name"
    ln -sfn "$source_dir" "$target_dir/$link_name"
    echo "  ✓ skill: $link_name"
  done < "$LINKS_FILE"
}

# Mirror every skill of each configured external source directory into
# skills/<category>/ as per-skill symlinks, and drop symlinks whose source
# skill no longer exists, so externally maintained skills are picked up
# without anyone hand-linking each new one.
sync_external_skills() {
  [[ -f "$EXTERNAL_SKILLS_CONF" ]] || return 0
  echo "→ External skill sources ($EXTERNAL_SKILLS_CONF)"
  shopt -s nullglob
  local category src_dir category_dir entry raw skill_dir name
  while read -r category src_dir; do
    [[ -z "$category" || "$category" == \#* ]] && continue
    if [[ ! -d "$src_dir" ]]; then
      echo "  ! $category: source dir missing, skipped: $src_dir" >&2
      continue
    fi
    category_dir="$SKILLS_SRC/$category"
    mkdir -p "$category_dir"
    for entry in "$category_dir"/*; do
      [[ -L "$entry" ]] || continue
      raw="$(readlink "$entry" 2>/dev/null || true)"
      [[ "$raw" == "$src_dir"/* ]] || continue
      [[ -f "$entry/SKILL.md" ]] && continue
      rm -f "$entry"
      echo "  ✓ prune ${category}.$(basename "$entry") (gone from source)"
    done
    for skill_dir in "$src_dir"/*/; do
      name="$(basename "$skill_dir")"
      [[ -f "$skill_dir/SKILL.md" ]] || continue
      # ln -n does not replace an existing real directory (it would nest the
      # link inside it), so clear whatever holds the name first.
      rm -rf "${category_dir:?}/$name"
      ln -sn "${skill_dir%/}" "$category_dir/$name"
      echo "  ✓ source: ${category}.${name} → ${skill_dir%/}"
    done
  done < "$EXTERNAL_SKILLS_CONF"
}

# ── 1. Claude Code (~/.claude) ─────────────────────────────────────
install_claude() {
  echo "→ Claude Code"
  mkdir -p "$CLAUDE_DIR/rules"
  ln -sfn "$RULES_SRC/coding.md" "$CLAUDE_DIR/rules/coding.md"
  echo "  ✓ linked rules/coding.md"
  link_skills "$CLAUDE_SKILLS_DIR"
}

# ── 2. Cursor (~/.cursor) ──────────────────────────────────────────
install_cursor() {
  echo "→ Cursor"
  mkdir -p "$CURSOR_DIR/rules"
  {
    echo "---"
    echo "description: General coding standards — style, error handling, typing, and dependency management"
    echo "alwaysApply: true"
    echo "---"
    echo
    cat "$RULES_SRC/coding.md"
  } > "$CURSOR_DIR/rules/coding.mdc"
  rm -f "$CURSOR_DIR/rules/coding.md"
  echo "  ✓ generated rules/coding.mdc from rules/coding.md"
  link_skills "$CURSOR_SKILLS_DIR"
}

# ── 3. Generic agents (~/.agents/skills) ───────────────────────────
install_agent_skills() {
  echo "→ Generic agents"
  link_skills "$AGENTS_SKILLS_DIR"
}

# ── 4. GitHub Copilot (~/.copilot/skills) ──────────────────────────
install_copilot_skills() {
  echo "→ GitHub Copilot"
  link_skills "$COPILOT_SKILLS_DIR"
}

# ── 5. GitHub Copilot IntelliJ plugin (~/.config/github-copilot/intellij) ──
install_copilot_intellij() {
  echo "→ GitHub Copilot (IntelliJ)"
  mkdir -p "$COPILOT_INTELLIJ_DIR"
  ln -sfn "$RULES_SRC/coding.md" "$COPILOT_INTELLIJ_DIR/global-copilot-instructions.md"
  echo "  ✓ linked rules/coding.md → global-copilot-instructions.md"
}

# ── 6. Global agent instructions (every tool's user-scope context) ──
# APM writes ~/.codex/AGENTS.md, ~/.cursor/AGENTS.md, ~/.gemini/GEMINI.md, …
# and ~/.claude/rules/; a local package is copied, so re-run after editing.
install_global_instructions() {
  echo "→ Global agent instructions"
  # MCP servers are managed separately in ~/.apm/apm.yml. Reinstalling them
  # here can conflict with native connections already present in a tool.
  # Claude profiles under CLAUDE_CONFIG_DIR symlink rules/ back to ~/.claude,
  # so target ~/.claude directly; inside a profile APM refuses the symlink and
  # falls back to a duplicate profile CLAUDE.md.
  env -u CLAUDE_CONFIG_DIR apm install -g --only apm "$GLOBAL_PKG"
  env -u CLAUDE_CONFIG_DIR apm compile -g
}

# ── 7. Pi (~/.pi/agent) ────────────────────────────────────────────
# APM has no `pi` target, so neither `apm compile -g` nor APM's MCP install in
# section 6 writes anything Pi reads. Pi loads one user-scope context file and
# one user-scope MCP file per agent directory, so publish both here.
# No skill links: Pi reads ~/.agents/skills/ directly (section 3), and a second
# copy under <agent-dir>/skills/ would only collide on name — Pi keeps the
# first hit and warns about the duplicate.
PI_MANAGED_MARKER="<!-- dotai: generated by scripts/install.sh; local edits are overwritten -->"

# Move a hand-authored file or symlink aside once instead of replacing it.
# A symlink counts as unmanaged: it usually points at a dotfiles checkout, and
# silently converting it into a generated file would cut that path loose. Once a
# backup exists the user has not merged it yet, so refuse rather than destroy
# the only copy.
back_up_unmanaged() {
  local path="$1" backup="$1.bak"
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ -e "$backup" || -L "$backup" ]]; then
    echo "  ! $path is not managed by dotai and $backup already exists; merge it and re-run" >&2
    return 1
  fi
  mv "$path" "$backup"
  echo "  ✓ moved existing $path → $backup"
}

# Merge the managed servers (public .mcp.json plus the private ones) into Pi's
# own MCP file. Entries this script
# wrote last run are refreshed when the user left them alone; anything the user
# added or edited wins, so an ordinary run never discards their customization.
# The sidecar records what was written, which is the only way to tell the two
# apart once the file is on disk.
merge_managed_mcp() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, os, sys, tempfile

src, dest, state_path = sys.argv[1], sys.argv[2], sys.argv[3]
public = json.load(open(src))["mcpServers"]
config = {}
if os.path.isfile(dest):
    try:
        with open(dest) as fh:
            config = json.load(fh)
    except (json.JSONDecodeError, AttributeError) as error:
        sys.exit("  ! %s is not a Pi MCP config (%s); fix or remove it" % (dest, error))
if not isinstance(config, dict):
    sys.exit("  ! %s is not a JSON object; fix or remove it" % dest)
servers = config.get("mcpServers", {})
if not isinstance(servers, dict):
    sys.exit("  ! %s has a non-object mcpServers; fix or remove it" % dest)
written = {}
if os.path.isfile(state_path):
    try:
        with open(state_path) as fh:
            written = json.load(fh).get("written", {})
    except (json.JSONDecodeError, AttributeError):
        written = {}
if not isinstance(written, dict):
    written = {}

# Pi counts names differing only in - and _ as the same server and rejects the
# second, so collisions are detected on the normalized name.
def normalize(name):
    return name.replace("_", "-")

managed = {}
# Retire servers a public dependency dropped, while their on-disk entry is still
# exactly what was written. An edited one belongs to the user now.
for name in list(written):
    if name in public:
        continue
    if name in servers and servers[name] == written[name]:
        del servers[name]

for name, entry in public.items():
    key = normalize(name)
    if key in managed:
        continue
    owned = name in written
    if name in servers:
        # Refresh only an entry still holding exactly what this script wrote.
        # Ownership is never claimed for a pre-existing same-name entry: a user
        # who configured the server by hand must not have it rewritten later
        # just because their value happened to match the public one.
        if owned and written[name] == servers[name]:
            servers[name] = entry
            managed[key] = name
    elif not any(normalize(other) == key for other in servers):
        servers[name] = entry
        managed[key] = name
# Nothing configured, nothing recorded, nothing to record: leave a fresh machine
# untouched. A stale sidecar must still be cleared, so it counts as work.
if not config and not servers and not public and not written:
    sys.exit(0)
# Top-level options such as autoEnableCodemode sit beside mcpServers; keep them.
config["mcpServers"] = servers

for path, payload in ((dest, config), (state_path, {"written": {n: public[n] for n in managed.values()}})):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".dotai.")
    with os.fdopen(fd, "w") as fh:
        json.dump(payload, fh, indent=2)
        fh.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
PY
}

install_pi() {
  echo "→ Pi"
  mkdir -p "$PI_AGENT_DIR"
  local staging dest
  staging="$(mktemp -d)"
  dest="$PI_AGENT_DIR/AGENTS.md"
  if [[ -d "$dest" ]]; then
    rm -rf "$staging"
    echo "  ! $dest is a directory; move it aside" >&2
    return 1
  fi
  if ( cd "$GLOBAL_PKG" && apm compile --root "$staging" --target agents >/dev/null ); then
    # Judged by the marker: a generated file is replaced, anything else — a
    # hand-written file or a symlink, even one whose target still carries the
    # marker — is backed up. Tested in separate statements because `A || B && C`
    # groups as `(A || B) && C` and would let a marker in the link target skip
    # the backup.
    local unmanaged=0
    if [[ -L "$dest" ]]; then
      unmanaged=1
    elif [[ -f "$dest" ]] && ! grep -qF "$PI_MANAGED_MARKER" "$dest"; then
      unmanaged=1
    fi
    if [[ "$unmanaged" -eq 1 ]] && ! back_up_unmanaged "$dest"; then
      rm -rf "$staging"
      return 1
    fi
    # rules/coding.md lives outside $GLOBAL_PKG, so the compiled file alone
    # would leave Pi without the coding standards the other tools get. mktemp
    # keeps the write out of a predictable path a pre-existing symlink could
    # redirect.
    local tmp
    tmp="$(mktemp "$PI_AGENT_DIR/.AGENTS.md.XXXXXX")"
    {
      echo "$PI_MANAGED_MARKER"
      cat "$staging/AGENTS.md"
      echo
      cat "$RULES_SRC/coding.md"
    } > "$tmp"
    mv -f "$tmp" "$dest"
    echo "  ✓ compiled global instructions + rules/coding.md → $dest"
    rm -rf "$staging"
  else
    rm -rf "$staging"
    echo "  ! failed to compile global instructions for Pi" >&2
    return 1
  fi

  install_pi_mcp
}

# Write the servers Pi should get to $1: the public .mcp.json plus, when the
# private repo is present, `sync-mcp --emit-pi`. A name in both is an error
# rather than a silent override, because the two would install different URLs.
managed_mcp_source() {
  local out="$1" private_json
  private_json="$(mktemp)"
  if [[ -x "$SYNC_MCP" ]]; then
    if ! "$SYNC_MCP" --emit-pi > "$private_json"; then
      rm -f "$private_json"
      echo "  ! sync-mcp --emit-pi failed" >&2
      return 1
    fi
  else
    echo '{"mcpServers": {}}' > "$private_json"
  fi
  python3 -I - "$ROOT/.mcp.json" "$private_json" "$out" <<'PY'
import json, os, sys

public_path, private_path, out = sys.argv[1:4]
# A missing .mcp.json means no public servers; previously managed ones still
# have to be retired, so treat it as an empty set instead of bailing out.
public = json.load(open(public_path))["mcpServers"] if os.path.isfile(public_path) else {}
private = json.load(open(private_path))["mcpServers"]
both = sorted(set(public) & set(private))
if both:
    sys.exit("  ! declared in both the public and private manifest: " + ", ".join(both))
with open(out, "w") as fh:
    json.dump({"mcpServers": {**public, **private}}, fh)
PY
  local status=$?
  rm -f "$private_json"
  return "$status"
}

install_pi_mcp() {
  local mcp_dest="$PI_AGENT_DIR/mcp.json" source_json
  # The checked-in .mcp.json holds the public servers APM installs per target;
  # Pi reads the same {"mcpServers": …} shape from its agent directory. Merge a
  # copy instead of linking: `pi mcp add`, and enable/exposure changes in /mcp,
  # write this file, and a link would put the user's servers — and any headers
  # or tokens they carry — into the checkout.
  if [[ ! -f "$ROOT/.mcp.json" ]]; then
    # Nothing public to install, but servers this script installed earlier still
    # have to be retired, so the merge runs with an empty public set.
    echo "  ! .mcp.json is missing — run 'apm install' to generate it" >&2
  fi
  if [[ -d "$mcp_dest" ]]; then
    echo "  ! $mcp_dest is a directory; move it aside" >&2
    return 1
  fi
  # A symlink is nearly always a dotfiles checkout: merging through it would
  # then replace the link with a regular file and detach that path.
  if [[ -L "$mcp_dest" ]]; then
    if ! back_up_unmanaged "$mcp_dest"; then
      return 1
    fi
  fi
  source_json="$(mktemp)"
  if ! managed_mcp_source "$source_json" \
    || ! merge_managed_mcp "$source_json" "$mcp_dest" "$PI_AGENT_DIR/.dotai-managed-mcp.json"; then
    rm -f "$source_json"
    return 1
  fi
  rm -f "$source_json"
  echo "  ✓ merged public and private servers → $mcp_dest"
}

# ── 8. Remove the retired claude-tabs command ──────────────────────
remove_legacy_command() {
  local command_path="$BIN_DIR/claude-tabs"
  if [[ -L "$command_path" && "$(readlink "$command_path")" == "$ROOT/scripts/claude-tabs.sh" ]]; then
    rm -f "$command_path"
    echo "  ✓ removed retired command: $command_path"
  fi
}

# ── 9. Migrate the private repo's old mount point ──────────────────
# The private repo used to be mounted at skills/internal/. A pull moves the
# gitlink but leaves the old checkout behind, where it would be published a
# second time as the "internal" skill category. It is a git checkout that may
# hold unsaved work, so it is only removed when nothing in it would be lost.
migrate_legacy_internal_checkout() {
  local legacy="$ROOT/skills/internal"
  [[ -e "$legacy" ]] || return 0
  if [[ -d "$legacy" && -z "$(ls -A "$legacy")" ]]; then
    rmdir "$legacy"
    echo "  ✓ removed empty legacy $legacy"
    return 0
  fi
  local manual="rm -rf '$legacy' '$ROOT/.git/modules/skills/internal'"
  if [[ "$(git -C "$legacy" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$legacy" && pwd -P)" ]]; then
    echo "error: $legacy is a leftover of the old private-repo location (now internal/) but not a git checkout." >&2
    echo "Check its contents, then remove it: $manual" >&2
    return 1
  fi

  local problems=()
  [[ -z "$(git -C "$legacy" status --porcelain --untracked-files=all)" ]] \
    || problems+=("modified or untracked files — git -C '$legacy' status")
  [[ -z "$(git -C "$legacy" stash list)" ]] \
    || problems+=("a stash — git -C '$legacy' stash list")
  [[ -n "$(git -C "$legacy" branch -r --contains HEAD 2>/dev/null)" ]] \
    || problems+=("commits not on any remote branch — git -C '$legacy' log --oneline HEAD --not --remotes")
  if [[ "${#problems[@]}" -gt 0 ]]; then
    echo "error: $legacy is a leftover of the old private-repo location (now internal/) and holds:" >&2
    printf '  - %s\n' "${problems[@]}" >&2
    echo "Save that work, then remove it: $manual" >&2
    return 1
  fi

  local gitdir
  gitdir="$(git -C "$legacy" rev-parse --absolute-git-dir)"
  rm -rf "$legacy"
  if [[ "$gitdir" == "$(cd "$ROOT/.git" && pwd -P)/modules/skills/internal" ]]; then
    rm -rf "$gitdir"
  fi
  if git -C "$ROOT" config --get-regexp '^submodule\.skills/internal\.' >/dev/null; then
    git -C "$ROOT" config --remove-section submodule.skills/internal
  fi
  echo "  ✓ removed legacy $legacy (clean, everything pushed)"
}

# ── 10. Bring internal/ to the commit dotai pins ───────────────────
# `git submodule update` checks out the pinned commit detached, which would
# silently move someone developing in internal/ off their branch. A checkout
# on a branch is therefore left where it is; only a detached one (the normal
# consumer state) or a missing one follows the pin.
update_internal_checkout() {
  local branch
  if branch="$(git -C "$INTERNAL_DIR" symbolic-ref -q --short HEAD 2>/dev/null)" \
    && [[ "$(git -C "$INTERNAL_DIR" rev-parse --show-toplevel)" == "$(cd "$INTERNAL_DIR" && pwd -P)" ]]; then
    local pinned head
    pinned="$(git -C "$ROOT" ls-tree HEAD internal | awk '{ print $3 }')"
    head="$(git -C "$INTERNAL_DIR" rev-parse HEAD)"
    if [[ "$head" == "$pinned" ]]; then
      echo "  · internal/ is on branch $branch at the pinned commit; left as is"
    else
      echo "  · internal/ is on branch $branch at ${head:0:7}; dotai pins ${pinned:0:7}. Left as is — run 'git -C internal switch --detach $pinned' to follow the pin"
    fi
    return 0
  fi
  # Private skills are optional for users without access to dotai-internal.
  if ! git -C "$ROOT" submodule update --init internal; then
    echo "warning: internal/ not updated (no access to NoSugarCoffee/dotai-internal, or local changes?); internal.* skills skipped or stale." >&2
  fi
}

# ── Main ───────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
Usage: bash scripts/install.sh [option]
  (none)                       publish rules and skills, sync MCP servers, warn on MCP drift
  --list                       print the resolved "<link-name>\t<source-dir>" pairs and exit
  --sync-mcp [--dry-run] [--target claude,codex]
                               only sync MCP servers to Claude Code and Codex
  --check-mcp                  report MCP drift across Claude Code, Codex, and Pi; exit 1 on drift
  --adopt-mcp NAME             declare a hand-added server in internal/mcp/apm.yml, then install
  --except-mcp TOOL NAME       allow a server in one CLI only (internal/mcp/exceptions.conf)
USAGE
}

require_sync_mcp() {
  if [[ ! -x "$SYNC_MCP" ]]; then
    echo "error: $SYNC_MCP is unavailable. Run bash scripts/install.sh to initialize the internal/ submodule; private repository access is required." >&2
    return 1
  fi
}

# Claude profiles set CLAUDE_CONFIG_DIR; APM must write the shared ~/.claude.json.
sync_private_mcp() {
  require_sync_mcp
  env -u CLAUDE_CONFIG_DIR "$SYNC_MCP" --public-mcp "$ROOT/.mcp.json" "$@"
}

run_private_sync() {
  echo "→ MCP servers (Claude Code, Codex)"
  if [[ ! -x "$SYNC_MCP" ]]; then
    echo "  · private MCP sync skipped (internal/ not initialised)"
    return 0
  fi
  sync_private_mcp
}

# The check, adopt and except modes read each CLI's live configuration.
run_sync_mcp_live() {
  require_sync_mcp
  "$SYNC_MCP" "$@" --public-mcp "$ROOT/.mcp.json" \
    --claude-json "$HOME/.claude.json" --pi-mcp "$PI_AGENT_DIR/mcp.json"
}

check_mcp() {
  run_sync_mcp_live --check
}

# Run last by a plain install: drift is reported, never fatal, so one stray
# server does not block unrelated skill updates.
warn_on_mcp_drift() {
  [[ -x "$SYNC_MCP" ]] || return 0
  echo "→ MCP drift check"
  if ! check_mcp; then
    echo "  ! MCP drift found (see above); bash scripts/install.sh --check-mcp exits non-zero until it is resolved" >&2
  fi
}

main() {
  local list_only=0
  case "${1:-}" in
    --sync-mcp)
      shift
      sync_private_mcp "$@"
      return
      ;;
    --check-mcp)
      [[ "$#" -eq 1 ]] || { usage >&2; return 1; }
      check_mcp
      return
      ;;
    --adopt-mcp)
      [[ "$#" -eq 2 ]] || { usage >&2; return 1; }
      run_sync_mcp_live --adopt "$2"
      ;;
    --except-mcp)
      [[ "$#" -eq 3 ]] || { usage >&2; return 1; }
      run_sync_mcp_live --except "$2" "$3"
      check_mcp
      return
      ;;
    --list)
      if [[ "$#" -ne 1 ]]; then
        usage >&2
        return 1
      fi
      list_only=1
      ;;
    -h|--help)
      usage
      return
      ;;
    "") ;;
    *)
      usage >&2
      return 1
      ;;
  esac

  LINKS_FILE="$(mktemp)"
  trap 'rm -f "$LINKS_FILE"' EXIT

  if [[ "$list_only" -eq 1 ]]; then
    { resolve_local_skills; resolve_internal_skills; resolve_vendored_skills; } > "$LINKS_FILE"
    assert_unique_link_names
    sort "$LINKS_FILE"
    return 0
  fi

  migrate_legacy_internal_checkout

  update_internal_checkout

  sync_external_skills

  echo "→ Resolving skills"
  { resolve_local_skills; resolve_internal_skills; resolve_vendored_skills; } > "$LINKS_FILE"
  assert_unique_link_names
  echo "  ✓ $(wc -l < "$LINKS_FILE" | tr -d ' ') skills"

  install_claude
  install_cursor
  install_agent_skills
  install_copilot_skills
  install_copilot_intellij
  install_global_instructions
  run_private_sync
  install_pi
  remove_legacy_command
  warn_on_mcp_drift

  echo ""
  echo "✅ dotai installed."
  echo "   Skills   : $SKILLS_SRC + $APM_MODULES (symlinked)"
  echo "   Rules    : $CLAUDE_DIR/rules/coding.md, $CURSOR_DIR/rules/coding.mdc, $COPILOT_INTELLIJ_DIR/global-copilot-instructions.md"
  echo "   Global   : $GLOBAL_PKG via apm install -g --only apm + apm compile -g"
  echo "   Pi       : $PI_AGENT_DIR/AGENTS.md (compiled from $GLOBAL_PKG)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
