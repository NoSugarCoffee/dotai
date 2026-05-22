#!/usr/bin/env bash
# Verifies that ~/.claude/skills/ contains namespaced symlinks from this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"
SKILLS_SRC="$ROOT/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

EXPECTED=(
  "code:diagnose"
  "code:code-review"
  "code:improve-codebase-architecture"
  "code:impeccable"
  "docs:grill-with-docs"
  "docs:handoff"
  "docs:project-readme-author"
  "creative:logo-generator"
  "creative:project-logo-author"
  "creative:hyperframes"
  "writing:baoyu-translate"
  "utils:skill-creator"
)

FLAT_SHOULD_NOT_EXIST=(
  "diagnose"
  "code-review"
  "improve-codebase-architecture"
  "impeccable"
  "grill-with-docs"
  "handoff"
  "project-readme-author"
  "logo-generator"
  "project-logo-author"
  "hyperframes"
  "baoyu-translate"
  "skill-creator"
)

PASS=0
FAIL=0

for name in "${EXPECTED[@]}"; do
  if [[ -L "$CLAUDE_SKILLS_DIR/$name" ]]; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ MISSING: $name"
    FAIL=$((FAIL + 1))
  fi
done

for name in "${FLAT_SHOULD_NOT_EXIST[@]}"; do
  if [[ -L "$CLAUDE_SKILLS_DIR/$name" ]]; then
    resolved="$(realpath "$CLAUDE_SKILLS_DIR/$name" 2>/dev/null || true)"
    if [[ "$resolved" == "$SKILLS_SRC"/* ]]; then
      echo "  ✗ STALE FLAT SYMLINK: $name"
      FAIL=$((FAIL + 1))
    fi
  fi
done

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ All $PASS checks passed."
  exit 0
else
  echo "❌ $FAIL checks failed, $PASS passed."
  exit 1
fi
