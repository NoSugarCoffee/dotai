#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
git -C "$ROOT" pull --ff-only || true
# Installs what apm.lock.yaml pins. Refreshing upstream refs is 'apm update',
# a deliberate act, not something a sync should do silently.
#
# --frozen is not used: it rejects op7418/logo-generator-skill, a bare
# SKILL.md repo with no apm.yml manifest of its own.
(cd "$ROOT" && apm install)
bash "$ROOT/scripts/install.sh"
echo "dotai synced."
