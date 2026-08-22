#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# dotai install.sh
# Installs skills and rules from this repo into all local AI agent
# directories using SYMLINKS so updates are reflected immediately.
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"
SKILLS_SRC="$ROOT/skills"
RULES_SRC="$ROOT/rules"

BIN_SRC="$ROOT/scripts"
BIN_DIR="$HOME/.local/bin"

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

# ── Helpers ────────────────────────────────────────────────────────

# Remove every symlink in target_dir that resolves into SKILLS_SRC (this repo).
# Keeps installs idempotent without special cases (old reviewer aliases, renamed skills).
prune_symlinks_into_skills_dir() {
  local target_dir="$1"
  local abs_skills="$2"
  shopt -s nullglob
  local entry raw resolved
  for entry in "${target_dir}"/*; do
    [[ -L "$entry" ]] || continue
    # Use readlink for the raw target (works even for broken symlinks).
    raw="$(readlink "$entry" 2>/dev/null || true)"
    [[ -z "$raw" ]] && continue
    # Prefer fully resolved path; fall back to raw target for broken links.
    resolved="$(realpath "$entry" 2>/dev/null || readlink -f "$entry" 2>/dev/null || echo "$raw")"
    if [[ "$resolved" == "$abs_skills" || "$resolved" == "$abs_skills"/* ]]; then
      rm -f "${entry:?}"
      echo "  ✓ prune $(basename "$entry")"
    fi
  done
}

# Symlink every skill under SKILLS_SRC into target_dir as {category}:{skill-name}.
link_skills() {
  local target_dir="$1"
  local abs_skills
  abs_skills="$(cd "$SKILLS_SRC" && pwd -P)"

  mkdir -p "$target_dir"
  prune_symlinks_into_skills_dir "$target_dir" "$abs_skills"

  for category_dir in "$SKILLS_SRC"/*/; do
    local category
    category="$(basename "$category_dir")"
    for skill_dir in "$category_dir"*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name link_name
      skill_name="$(basename "$skill_dir")"
      link_name="${category}.${skill_name}"
      rm -rf "${target_dir:?}/$link_name"
      ln -sfn "$skill_dir" "$target_dir/$link_name"
      echo "  ✓ skill: $link_name → $target_dir/$link_name"
    done
  done
}

# Mirror every skill of each configured external source directory into
# skills/<category>/ as per-skill symlinks, and drop symlinks whose source
# skill no longer exists, so link_skills sees externally maintained skills
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
  sync_external_skills
  install_claude
  install_cursor
  install_agent_skills
  install_copilot_skills
  install_copilot_intellij
  install_bin

  echo ""
  echo "✅ dotai installed."
  echo "   Skills   : $SKILLS_SRC (symlinked)"
  echo "   Rules    : $CLAUDE_DIR/rules/coding.md, $CURSOR_DIR/rules/coding.mdc, $COPILOT_INTELLIJ_DIR/global-copilot-instructions.md"
  echo "   Commands : $BIN_DIR/claude-tabs"
}

main
