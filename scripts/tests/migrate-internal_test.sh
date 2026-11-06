#!/usr/bin/env bash
# Exercises migrate_legacy_internal_checkout against scratch repositories that
# mimic a dotai checkout still holding the private repo at skills/internal/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../install.sh
source "$REPO_ROOT/scripts/install.sh"

FAILURES=0
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

fail() {
  echo "  ✗ $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "  ✓ $1"
}

# Prints the path of a fresh dotai-like repo whose skills/internal is a real
# submodule cloned from a bare remote, as an existing machine would have it.
make_root() {
  local name="$1" remote="$SCRATCH/$1-remote.git" seed="$SCRATCH/$1-seed" root="$SCRATCH/$1-root"
  git init -q --bare "$remote"
  git init -q -b main "$seed"
  echo skill > "$seed/README.md"
  git -C "$seed" add README.md
  git -C "$seed" commit -qm seed
  git -C "$seed" push -q "$remote" main
  git init -q -b main "$root"
  git -C "$root" -c protocol.file.allow=always submodule add -q "$remote" skills/internal >/dev/null 2>&1
  git -C "$root" commit -qm "add submodule"
  echo "$root"
}

run_migration() {
  local root="$1"
  ROOT="$root"
  MIGRATION_OUTPUT="$(migrate_legacy_internal_checkout 2>&1)" && MIGRATION_STATUS=0 || MIGRATION_STATUS=$?
}

test_clean_checkout_is_removed() {
  local root
  root="$(make_root clean)"
  run_migration "$root"
  if [[ "$MIGRATION_STATUS" -eq 0 && ! -e "$root/skills/internal" && ! -e "$root/.git/modules/skills/internal" ]]; then
    pass "clean legacy checkout removed"
  else
    fail "clean legacy checkout removed (status $MIGRATION_STATUS): $MIGRATION_OUTPUT"
  fi
  if git -C "$root" config --get-regexp '^submodule\.skills/internal\.' >/dev/null; then
    fail "legacy submodule config section dropped"
  else
    pass "legacy submodule config section dropped"
  fi
}

assert_kept() {
  local root="$1" label="$2" expected="$3"
  run_migration "$root"
  if [[ "$MIGRATION_STATUS" -ne 0 && -d "$root/skills/internal" && "$MIGRATION_OUTPUT" == *"$expected"* ]]; then
    pass "$label"
  else
    fail "$label (status $MIGRATION_STATUS): $MIGRATION_OUTPUT"
  fi
}

test_untracked_file_stops() {
  local root
  root="$(make_root untracked)"
  touch "$root/skills/internal/draft.md"
  assert_kept "$root" "untracked file stops the migration" "untracked"
}

test_stash_stops() {
  local root
  root="$(make_root stash)"
  echo change >> "$root/skills/internal/README.md"
  git -C "$root/skills/internal" stash -q
  assert_kept "$root" "stash stops the migration" "stash"
}

test_unpushed_commit_stops() {
  local root
  root="$(make_root unpushed)"
  echo change >> "$root/skills/internal/README.md"
  git -C "$root/skills/internal" commit -qam local
  assert_kept "$root" "unpushed commit stops the migration" "not on any remote branch"
}

test_empty_directory_is_removed() {
  local root="$SCRATCH/empty-root"
  mkdir -p "$root/skills/internal"
  git init -q "$root"
  run_migration "$root"
  if [[ "$MIGRATION_STATUS" -eq 0 && ! -e "$root/skills/internal" ]]; then
    pass "empty legacy directory removed"
  else
    fail "empty legacy directory removed (status $MIGRATION_STATUS): $MIGRATION_OUTPUT"
  fi
}

test_no_legacy_directory_is_silent() {
  local root="$SCRATCH/none-root"
  mkdir -p "$root/skills"
  git init -q "$root"
  run_migration "$root"
  if [[ "$MIGRATION_STATUS" -eq 0 && -z "$MIGRATION_OUTPUT" ]]; then
    pass "no legacy directory: nothing done"
  else
    fail "no legacy directory: nothing done (status $MIGRATION_STATUS): $MIGRATION_OUTPUT"
  fi
}

test_clean_checkout_is_removed
test_untracked_file_stops
test_stash_stops
test_unpushed_commit_stops
test_empty_directory_is_removed
test_no_legacy_directory_is_silent

if [[ "$FAILURES" -eq 0 ]]; then
  echo "✅ migrate-internal: all passed"
else
  echo "❌ migrate-internal: $FAILURES failed"
  exit 1
fi
