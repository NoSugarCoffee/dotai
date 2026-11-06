#!/usr/bin/env bash
# Exercises update_internal_checkout: a detached internal/ follows the commit
# dotai pins, while a branch someone is working on is never moved.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../install.sh
source "$REPO_ROOT/scripts/install.sh"

FAILURES=0
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always

fail() {
  echo "  ✗ $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "  ✓ $1"
}

# Prints the path of a dotai-like repo pinning internal/ at the remote's second
# commit; the first commit is reachable for tests that need an older one.
make_root() {
  local name="$1" remote="$SCRATCH/$1-remote.git" seed="$SCRATCH/$1-seed" root="$SCRATCH/$1-root"
  git init -q --bare "$remote"
  git init -q -b main "$seed"
  echo one > "$seed/file"
  git -C "$seed" add file
  git -C "$seed" commit -qm one
  echo two > "$seed/file"
  git -C "$seed" commit -qam two
  git -C "$seed" push -q "$remote" main
  git init -q -b main "$root"
  git -C "$root" submodule add -q "$remote" internal >/dev/null 2>&1
  git -C "$root" commit -qm "pin internal"
  echo "$root"
}

pinned_commit() {
  git -C "$1" ls-tree HEAD internal | awk '{ print $3 }'
}

test_branch_is_left_alone() {
  local root tip
  root="$(make_root branch)"
  git -C "$root/internal" switch -q -c feature
  echo three > "$root/internal/file"
  git -C "$root/internal" commit -qam three
  tip="$(git -C "$root/internal" rev-parse HEAD)"
  ROOT="$root" INTERNAL_DIR="$root/internal"
  local output
  output="$(update_internal_checkout 2>&1)"
  if [[ "$(git -C "$root/internal" rev-parse HEAD)" == "$tip" \
    && "$(git -C "$root/internal" symbolic-ref -q --short HEAD)" == feature ]]; then
    pass "branch checkout keeps its tip"
  else
    fail "branch checkout keeps its tip: $output"
  fi
  if [[ "$output" == *"feature"* && "$output" == *"pins"* ]]; then
    pass "branch checkout ahead of the pin is reported"
  else
    fail "branch checkout ahead of the pin is reported: $output"
  fi
}

test_detached_follows_pin() {
  local root
  root="$(make_root detached)"
  git -C "$root/internal" checkout -q --detach HEAD~1
  ROOT="$root" INTERNAL_DIR="$root/internal"
  update_internal_checkout >/dev/null 2>&1
  if [[ "$(git -C "$root/internal" rev-parse HEAD)" == "$(pinned_commit "$root")" ]]; then
    pass "detached checkout moves to the pinned commit"
  else
    fail "detached checkout moves to the pinned commit"
  fi
}

test_uninitialised_is_cloned() {
  local root
  root="$(make_root fresh)"
  git -C "$root" submodule deinit -q -f internal
  ROOT="$root" INTERNAL_DIR="$root/internal"
  update_internal_checkout >/dev/null 2>&1
  if [[ "$(git -C "$root/internal" rev-parse HEAD 2>/dev/null)" == "$(pinned_commit "$root")" ]]; then
    pass "uninitialised internal/ is checked out at the pin"
  else
    fail "uninitialised internal/ is checked out at the pin"
  fi
}

test_branch_is_left_alone
test_detached_follows_pin
test_uninitialised_is_cloned

if [[ "$FAILURES" -eq 0 ]]; then
  echo "✅ internal-update: all passed"
else
  echo "❌ internal-update: $FAILURES failed"
  exit 1
fi
