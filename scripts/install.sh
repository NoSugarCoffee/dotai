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
# Usage: install.sh [--list]
#   --list   print the resolved "<link-name>\t<source-dir>" pairs and exit,
#            without touching any tool directory
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"
SKILLS_SRC="$ROOT/skills"
APM_MODULES="$ROOT/apm_modules"
RULES_SRC="$ROOT/rules"

BIN_SRC="$ROOT/scripts"
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

  local skill category matches count status=0
  while read -r skill category; do
    [[ -z "$skill" || "$skill" == \#* ]] && continue
    matches="$(awk -F'\t' -v n="$skill" '$1 == n { print $2 }' "$index")"
    count="$(printf '%s' "$matches" | grep -c . || true)"
    if [[ "$count" -eq 0 ]]; then
      echo "  ! ${category}.${skill}: no SKILL.md in apm_modules/ declares this name — is it pinned in apm.yml?" >&2
      status=1
    elif [[ "$count" -gt 1 ]]; then
      echo "  ! ${category}.${skill}: ambiguous, $count skills declare this name:" >&2
      printf '      %s\n' $matches >&2
      status=1
    else
      printf '%s\t%s\n' "${category}.${skill}" "$matches"
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

# ── 6. Command-line tools (~/.local/bin) ───────────────────────────
install_bin() {
  echo "→ Commands"
  mkdir -p "$BIN_DIR"
  ln -sfn "$BIN_SRC/claude-tabs.sh" "$BIN_DIR/claude-tabs"
  echo "  ✓ command: claude-tabs → $BIN_DIR/claude-tabs"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "  ! $BIN_DIR is not on your PATH" ;;
  esac
}

# ── Main ───────────────────────────────────────────────────────────
main() {
  local list_only=0
  [[ "${1:-}" == "--list" ]] && list_only=1

  LINKS_FILE="$(mktemp)"
  trap 'rm -f "$LINKS_FILE"' EXIT

  if [[ "$list_only" -eq 1 ]]; then
    { resolve_local_skills; resolve_vendored_skills; } > "$LINKS_FILE"
    assert_unique_link_names
    sort "$LINKS_FILE"
    return 0
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
  install_bin

  echo ""
  echo "✅ dotai installed."
  echo "   Skills   : $SKILLS_SRC + $APM_MODULES (symlinked)"
  echo "   Rules    : $CLAUDE_DIR/rules/coding.md, $CURSOR_DIR/rules/coding.mdc, $COPILOT_INTELLIJ_DIR/global-copilot-instructions.md"
  echo "   Commands : $BIN_DIR/claude-tabs"
}

main "$@"
