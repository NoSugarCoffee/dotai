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

CLAUDE_DIR="$HOME/.claude"
CURSOR_DIR="$HOME/.cursor"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
CURSOR_SKILLS_DIR="$HOME/.cursor/skills"
COPILOT_SKILLS_DIR="$HOME/.copilot/skills"
COPILOT_INTELLIJ_DIR="$HOME/.config/github-copilot/intellij"

# ── Helpers ────────────────────────────────────────────────────────

# Remove every symlink in target_dir that resolves into SKILLS_SRC (this repo).
# Keeps installs idempotent without special cases (old reviewer aliases, renamed skills).
prune_symlinks_into_skills_dir() {
  local target_dir="$1"
  local abs_skills="$2"
  shopt -s nullglob
  local entry resolved
  for entry in "${target_dir}"/*; do
    [[ -L "$entry" ]] || continue
    resolved=""
    resolved="$(realpath "$entry" 2>/dev/null || true)"
    if [[ -z "$resolved" ]]; then
      resolved="$(readlink -f "$entry" 2>/dev/null || true)"
    fi
    [[ -z "$resolved" ]] && continue
    if [[ "$resolved" == "$abs_skills" || "$resolved" == "$abs_skills"/* ]]; then
      rm -f "${entry:?}"
      echo "  ✓ prune $(basename "$entry")"
    fi
  done
}

# Symlink every top-level skill directory under SKILLS_SRC into target_dir.
link_skills() {
  local target_dir="$1"
  local abs_skills
  abs_skills="$(cd "$SKILLS_SRC" && pwd -P)"

  mkdir -p "$target_dir"
  prune_symlinks_into_skills_dir "$target_dir" "$abs_skills"

  for skill_dir in "$SKILLS_SRC"/*/; do
    local skill_name
    skill_name="$(basename "$skill_dir")"
    rm -rf "${target_dir:?}/$skill_name"
    ln -sfn "$skill_dir" "$target_dir/$skill_name"
    echo "  ✓ skill: $skill_name → $target_dir/$skill_name"
  done
}

# ── 1. Claude Code (~/.claude) ─────────────────────────────────────
install_claude() {
  echo "→ Claude Code"
  mkdir -p "$CLAUDE_DIR/rules"
  ln -sfn "$RULES_SRC/coding.md" "$CLAUDE_DIR/rules/coding.md"
  echo "  ✓ linked rules/coding.md"
}

# ── 2. Cursor (~/.cursor) ──────────────────────────────────────────
install_cursor() {
  echo "→ Cursor"
  mkdir -p "$CURSOR_DIR/rules"
  ln -sfn "$RULES_SRC/coding.md" "$CURSOR_DIR/rules/coding.md"
  echo "  ✓ linked rules/coding.md"
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

# ── Main ───────────────────────────────────────────────────────────
main() {
  install_claude
  install_cursor
  install_agent_skills
  install_copilot_skills
  install_copilot_intellij

  echo ""
  echo "✅ dotai installed."
  echo "   Skills : $SKILLS_SRC (symlinked)"
  echo "   Rules  : $CLAUDE_DIR/rules/coding.md, $CURSOR_DIR/rules/coding.md, $COPILOT_INTELLIJ_DIR/global-copilot-instructions.md"
}

main
