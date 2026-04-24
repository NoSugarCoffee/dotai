#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
mkdir -p "$HOME/.claude" "$HOME/.cursor" "$HOME/.agents"
cp "$ROOT/rules/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
mkdir -p "$HOME/.agents/skills"
cp -R "$ROOT/skills/." "$HOME/.agents/skills/"
echo "dotai installed into local agent directories."
