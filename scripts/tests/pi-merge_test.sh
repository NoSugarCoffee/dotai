#!/usr/bin/env bash
# Exercises install_pi_mcp: public servers from .mcp.json and private servers
# from `sync-mcp --emit-pi` merged into Pi's mcp.json, with ownership tracked
# in the sidecar so hand-made entries are never rewritten.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../install.sh
source "$REPO_ROOT/scripts/install.sh"

FAILURES=0
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

fail() {
  echo "  ✗ $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "  ✓ $1"
}

check() {
  local label="$1"
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

# A fresh fixture per test: dotai root with a public .mcp.json, a Pi agent dir,
# and a stub sync-mcp whose --emit-pi output comes from emit.json.
setup_fixture() {
  local name="$1"
  FIXTURE="$SCRATCH/$name"
  ROOT="$FIXTURE/root"
  PI_AGENT_DIR="$FIXTURE/pi"
  SYNC_MCP="$FIXTURE/sync-mcp"
  mkdir -p "$ROOT" "$PI_AGENT_DIR"
  cat > "$ROOT/.mcp.json" <<'JSON'
{"mcpServers": {"pub": {"type": "http", "url": "https://pub.example.test/mcp", "headers": {}}}}
JSON
  write_emit '{"mcpServers": {"priv": {"type": "http", "url": "https://priv.example.test/mcp"}}}'
  cat > "$SYNC_MCP" <<SH
#!/usr/bin/env bash
[[ "\$1" == "--emit-pi" ]] || exit 64
cat "$FIXTURE/emit.json"
SH
  chmod +x "$SYNC_MCP"
}

write_emit() {
  printf '%s\n' "$1" > "$FIXTURE/emit.json"
}

pi_has() {
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d["mcpServers"] else 1)' \
    "$PI_AGENT_DIR/mcp.json" "$1"
}

recorded() {
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d["written"] else 1)' \
    "$PI_AGENT_DIR/.dotai-managed-mcp.json" "$1"
}

test_private_server_written_and_recorded() {
  setup_fixture written
  install_pi_mcp >/dev/null
  check "private server written to Pi" pi_has priv
  check "public server written to Pi" pi_has pub
  check "private server recorded in sidecar" recorded priv
}

test_hand_entry_left_untouched() {
  setup_fixture hand
  cat > "$PI_AGENT_DIR/mcp.json" <<'JSON'
{"mcpServers": {"priv": {"type": "http", "url": "https://priv.example.test/mcp", "timeout": 600}}}
JSON
  local before
  before="$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["mcpServers"]["priv"], sort_keys=True))' "$PI_AGENT_DIR/mcp.json")"
  install_pi_mcp >/dev/null
  local after
  after="$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["mcpServers"]["priv"], sort_keys=True))' "$PI_AGENT_DIR/mcp.json")"
  check "hand-made same-name entry unchanged" test "$before" == "$after"
  if recorded priv; then fail "hand-made entry not claimed"; else pass "hand-made entry not claimed"; fi
}

test_collision_fails_and_leaves_pi_unchanged() {
  setup_fixture collision
  write_emit '{"mcpServers": {"pub": {"type": "http", "url": "https://other.example.test/mcp"}}}'
  echo '{"mcpServers": {}}' > "$PI_AGENT_DIR/mcp.json"
  local before status=0
  before="$(cat "$PI_AGENT_DIR/mcp.json")"
  install_pi_mcp >/dev/null 2>&1 || status=$?
  check "public/private collision fails" test "$status" -ne 0
  check "Pi config unchanged after collision" test "$before" == "$(cat "$PI_AGENT_DIR/mcp.json")"
}

test_dropped_private_server_retired() {
  setup_fixture retire
  install_pi_mcp >/dev/null
  write_emit '{"mcpServers": {}}'
  install_pi_mcp >/dev/null
  if pi_has priv; then fail "dropped private server retired"; else pass "dropped private server retired"; fi
  check "public server kept" pi_has pub
}

test_without_internal_only_public() {
  setup_fixture public-only
  SYNC_MCP="$FIXTURE/absent-sync-mcp"
  install_pi_mcp >/dev/null
  check "public server written without internal/" pi_has pub
  if pi_has priv; then fail "no private servers without internal/"; else pass "no private servers without internal/"; fi
}

test_private_server_written_and_recorded
test_hand_entry_left_untouched
test_collision_fails_and_leaves_pi_unchanged
test_dropped_private_server_retired
test_without_internal_only_public

if [[ "$FAILURES" -eq 0 ]]; then
  echo "✅ pi-merge: all passed"
else
  echo "❌ pi-merge: $FAILURES failed"
  exit 1
fi
