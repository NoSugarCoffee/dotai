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
    for root in "$SKILLS_SRC" "$APM_MODULES"; do
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

# Merge the public .mcp.json servers into Pi's own MCP file. Entries this script
# wrote last run are refreshed when the user left them alone; anything the user
# added or edited wins, so an ordinary run never discards their customization.
# The sidecar records what was written, which is the only way to tell the two
# apart once the file is on disk.
merge_public_mcp() {
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
for name, entry in public.items():
    key = normalize(name)
    if key in managed:
        continue
    if name in servers:
        # Refresh only an entry still holding exactly what was written before.
        if written.get(name) == servers[name]:
            servers[name] = entry
        managed[key] = name
    elif not any(normalize(other) == key for other in servers):
        servers[name] = entry
        managed[key] = name
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
  local staging dest mcp_dest
  staging="$(mktemp -d)"
  dest="$PI_AGENT_DIR/AGENTS.md"
  mcp_dest="$PI_AGENT_DIR/mcp.json"
  if [[ -d "$dest" ]]; then
    rm -rf "$staging"
    echo "  ! $dest is a directory; move it aside" >&2
    return 1
  fi
  if ( cd "$GLOBAL_PKG" && apm compile --root "$staging" --target agents >/dev/null ); then
    # Judged by the marker: a generated file is replaced, anything else — a
    # hand-written file or a symlink into a dotfiles checkout — is backed up.
    if [[ -L "$dest" ]] || [[ -f "$dest" ]] && ! grep -qF "$PI_MANAGED_MARKER" "$dest"; then
      if ! back_up_unmanaged "$dest"; then
        rm -rf "$staging"
        return 1
      fi
    fi
    # rules/coding.md lives outside $GLOBAL_PKG, so the compiled file alone
    # would leave Pi without the coding standards the other tools get.
    {
      echo "$PI_MANAGED_MARKER"
      cat "$staging/AGENTS.md"
      echo
      cat "$RULES_SRC/coding.md"
    } > "$dest.tmp"
    mv -f "$dest.tmp" "$dest"
    echo "  ✓ compiled global instructions + rules/coding.md → $dest"
    rm -rf "$staging"
  else
    rm -rf "$staging"
    echo "  ! failed to compile global instructions for Pi" >&2
    return 1
  fi

  # The checked-in .mcp.json holds the public servers APM installs per target;
  # Pi reads the same {"mcpServers": …} shape from its agent directory. Merge a
  # copy instead of linking: `pi mcp add`, and enable/exposure changes in /mcp,
  # write this file, and a link would put the user's servers — and any headers
  # or tokens they carry — into the checkout.
  if [[ -f "$ROOT/.mcp.json" ]]; then
    if [[ -d "$mcp_dest" ]]; then
      echo "  ! $mcp_dest is a directory; move it aside" >&2
      return 1
    fi
    if ! merge_public_mcp "$ROOT/.mcp.json" "$mcp_dest" "$PI_AGENT_DIR/.dotai-managed-mcp.json"; then
      return 1
    fi
    echo "  ✓ merged public servers → $mcp_dest"
  else
    echo "  ! .mcp.json is missing — run 'apm install' to generate it" >&2
  fi
}

# ── 8. Remove the retired claude-tabs command ──────────────────────
remove_legacy_command() {
  local command_path="$BIN_DIR/claude-tabs"
  if [[ -L "$command_path" && "$(readlink "$command_path")" == "$ROOT/scripts/claude-tabs.sh" ]]; then
    rm -f "$command_path"
    echo "  ✓ removed retired command: $command_path"
  fi
}

# ── Main ───────────────────────────────────────────────────────────
usage() {
  echo "Usage: bash scripts/install.sh [--list | --sync-mcp [--dry-run] [--target claude,codex]]"
}

sync_private_mcp() {
  local sync_script="$SKILLS_SRC/internal/scripts/sync-mcp"
  if [[ ! -x "$sync_script" ]]; then
    echo "error: private MCP sync script is unavailable. Run bash scripts/install.sh to initialize the pinned private submodule; private repository access is required." >&2
    return 1
  fi
  env -u CLAUDE_CONFIG_DIR "$sync_script" "$@"
}

main() {
  local list_only=0
  case "${1:-}" in
    --sync-mcp)
      shift
      sync_private_mcp "$@"
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
    { resolve_local_skills; resolve_vendored_skills; } > "$LINKS_FILE"
    assert_unique_link_names
    sort "$LINKS_FILE"
    return 0
  fi

  # Private skills are optional for users without access to dotai-internal.
  if ! git -C "$ROOT" submodule update --init skills/internal; then
    echo "warning: skills/internal not updated (no access to NoSugarCoffee/dotai-internal, or local changes?); internal.* skills skipped or stale." >&2
  fi

  sync_external_skills

  echo "→ Resolving skills"
  { resolve_local_skills; resolve_vendored_skills; } > "$LINKS_FILE"
  assert_unique_link_names
  echo "  ✓ $(wc -l < "$LINKS_FILE" | tr -d ' ') skills"

  install_claude
  install_cursor
  install_agent_skills
  install_copilot_skills
  install_copilot_intellij
  install_global_instructions
  install_pi
  remove_legacy_command

  echo ""
  echo "✅ dotai installed."
  echo "   Skills   : $SKILLS_SRC + $APM_MODULES (symlinked)"
  echo "   Rules    : $CLAUDE_DIR/rules/coding.md, $CURSOR_DIR/rules/coding.mdc, $COPILOT_INTELLIJ_DIR/global-copilot-instructions.md"
  echo "   Global   : $GLOBAL_PKG via apm install -g --only apm + apm compile -g"
  echo "   Pi       : $PI_AGENT_DIR/AGENTS.md (compiled from $GLOBAL_PKG)"
}

main "$@"
