#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
git -C "$ROOT" pull --ff-only || true
bash "$ROOT/scripts/install.sh"
echo "dotai synced."
