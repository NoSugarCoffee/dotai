#!/usr/bin/env bash
# Verifies that ~/.claude/skills/ matches what install.sh resolves: every
# skill published under its {category}.{name}, pointing at the right source,
# with no leftover links this repo used to own.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"
SKILLS_SRC="$ROOT/skills"
APM_MODULES="$ROOT/apm_modules"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

EXPECTED="$(mktemp)"
trap 'rm -f "$EXPECTED"' EXIT
bash "$ROOT/scripts/install.sh" --list > "$EXPECTED"

PASS=0
FAIL=0

while IFS=$'\t' read -r name source_dir; do
  link="$CLAUDE_SKILLS_DIR/$name"
  if [[ ! -L "$link" ]]; then
    echo "  ✗ MISSING: $name"
    FAIL=$((FAIL + 1))
    continue
  fi
  actual="$(readlink "$link")"
  if [[ "$actual" != "$source_dir" ]]; then
    echo "  ✗ WRONG SOURCE: $name → $actual (expected $source_dir)"
    FAIL=$((FAIL + 1))
    continue
  fi
  echo "  ✓ $name"
  PASS=$((PASS + 1))
done < "$EXPECTED"

# A link into this repo that install.sh no longer resolves is a leftover from
# a renamed or removed skill; install.sh prunes these, so finding one means
# the published state is stale.
shopt -s nullglob
for entry in "$CLAUDE_SKILLS_DIR"/*; do
  [[ -L "$entry" ]] || continue
  raw="$(readlink "$entry" 2>/dev/null || true)"
  [[ "$raw" == "$SKILLS_SRC"/* || "$raw" == "$APM_MODULES"/* ]] || continue
  cut -f1 "$EXPECTED" | grep -qx "$(basename "$entry")" && continue
  echo "  ✗ STALE LINK: $(basename "$entry") → $raw"
  FAIL=$((FAIL + 1))
done

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ All $PASS checks passed."
  exit 0
else
  echo "❌ $FAIL checks failed, $PASS passed."
  exit 1
fi
