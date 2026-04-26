#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# dotai install.sh
# Installs skills and rules from this repo into all local AI agent
# directories using SYMLINKS so updates are reflected immediately.
# ──────────────────────────────────────────────────────────────────
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"

SKILLS_SRC="$ROOT/skills"
RULES_SRC="$ROOT/rules"

# ── Helper ─────────────────────────────────────────────────────────
link_skill_dirs() {
  local target_dir="$1"
  mkdir -p "$target_dir"
  for skill_dir in "$SKILLS_SRC"/*/; do
    skill_name="$(basename "$skill_dir")"
    # Remove old copy/link then create fresh symlink
    rm -rf "${target_dir:?}/$skill_name"
    ln -sfn "$skill_dir" "$target_dir/$skill_name"
    echo "  ✓ linked skill: $skill_name → $target_dir/$skill_name"
  done
}

# ── 1. Claude Code: ~/.claude/ ─────────────────────────────────────
echo "→ Claude Code"
mkdir -p "$HOME/.claude"
cp "$RULES_SRC/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
echo "  ✓ copied CLAUDE.md"

# ── 2. Generic .agents skills (Antigravity / other agents) ─────────
echo "→ Generic agents (~/.agents/skills)"
link_skill_dirs "$HOME/.agents/skills"

# ── 3. Cursor: ~/.cursor/skills/ ───────────────────────────────────
# Cursor picks up skill directories from ~/.cursor/skills/.
echo "→ Cursor (~/.cursor/skills)"
CURSOR_SKILLS="$HOME/.cursor/skills"
mkdir -p "$CURSOR_SKILLS"
for skill_dir in "$SKILLS_SRC"/*/; do
  skill_name="$(basename "$skill_dir")"
  target="$CURSOR_SKILLS/$skill_name"
  rm -rf "$target"
  ln -sfn "$skill_dir" "$target"
  echo "  ✓ linked skill: $skill_name → $target"
done

# ── 4. GitHub Copilot: ~/.copilot/skills/ ──────────────────────────
echo "→ Copilot (~/.copilot/skills)"
link_skill_dirs "$HOME/.copilot/skills"

echo ""
echo "✅ dotai installed. All skills are symlinked — edits in $SKILLS_SRC are live everywhere."
