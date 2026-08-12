#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# claude-tabs
# Save the set of open interactive Claude Code sessions, and restore
# them later as zellij tabs — each in its own cwd, resumed in place.
#
#   claude-tabs save                 snapshot the sessions open now
#   claude-tabs list                 show live sessions and restore plan
#   claude-tabs restore [--dry-run]  reopen the snapshot as zellij tabs
#
# Requires: jq, zellij, /proc (Linux).
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SESSIONS_DIR="$CLAUDE_DIR/sessions"
PROJECTS_DIR="$CLAUDE_DIR/projects"
SNAPSHOT="$CLAUDE_DIR/open-sessions.json"
ZELLIJ_SESSION="claude-tabs"

die() {
  echo "claude-tabs: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
usage: claude-tabs <command>

  save                 snapshot the interactive sessions open right now
  list                 show live sessions and what a restore would do
  restore [--dry-run]  reopen the snapshot as zellij tabs

Snapshot lives at ~/.claude/open-sessions.json
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"
}

# starttime (field 22 of /proc/<pid>/stat) identifies a process across PID reuse.
# comm is parenthesized and may contain spaces and parens, so fields are counted
# from after the LAST ')', where starttime lands at field 20.
proc_start() {
  local pid="$1" stat rest
  [[ -r "/proc/$pid/stat" ]] || return 1
  stat="$(< "/proc/$pid/stat")"
  rest="${stat##*') '}"
  [[ "$rest" != "$stat" ]] || return 1
  awk '{ print $20 }' <<<"$rest"
}

is_live() {
  local pid="$1" want="$2" got
  got="$(proc_start "$pid")" || return 1
  [[ "$got" == "$want" ]]
}

# Only real terminal tabs: background agents, -p runs and SDK sessions are not
# things a human wants reopened.
registry_rows() {
  [[ -d "$SESSIONS_DIR" ]] || return 0
  local file
  shopt -s nullglob
  for file in "$SESSIONS_DIR"/*.json; do
    jq -r 'select(.kind == "interactive" and .entrypoint == "cli")
           | [.pid, .procStart, .sessionId, .cwd, .name] | @tsv' "$file" 2>/dev/null || true
  done
  shopt -u nullglob
}

live_rows() {
  local pid procstart sid cwd name
  while IFS=$'\t' read -r pid procstart sid cwd name; do
    [[ -n "$pid" && -n "$sid" ]] || continue
    if is_live "$pid" "$procstart"; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$procstart" "$sid" "$cwd" "$name"
    fi
  done < <(registry_rows)
}

live_session_ids() {
  live_rows | cut -f3
}

transcript_exists() {
  local sid="$1" match
  shopt -s nullglob
  match=("$PROJECTS_DIR"/*/"$sid.jsonl")
  shopt -u nullglob
  [[ ${#match[@]} -gt 0 ]]
}

# Paths are shown relative to $HOME purely so the tables stay readable.
pretty_path() {
  local path="$1"
  [[ "$path" == "$HOME"/* ]] && path="~${path#"$HOME"}"
  printf '%s' "$path"
}

cmd_save() {
  require jq

  local rows
  rows="$(live_rows)"
  [[ -n "$rows" ]] || die "no interactive sessions are running — nothing to save"

  # Same-directory temp + rename: an interrupted save must not leave a truncated
  # snapshot that a later restore would read as a shorter list of tabs.
  local tmp
  tmp="$(mktemp "$SNAPSHOT.XXXXXX")"
  printf '%s\n' "$rows" \
    | jq -R -s --argjson now "$(date +%s%3N)" \
        'split("\n")
         | map(select(length > 0) | split("\t"))
         | { savedAt: $now,
             sessions: map({ sessionId: .[2], cwd: .[3], name: .[4] }) }' \
    > "$tmp"
  mv "$tmp" "$SNAPSHOT"

  local count
  count="$(printf '%s\n' "$rows" | wc -l)"
  echo "saved $count session(s) to $(pretty_path "$SNAPSHOT")"
  local sid cwd name
  while IFS=$'\t' read -r _ _ sid cwd name; do
    printf '  %-24s %s\n' "$name" "$(pretty_path "$cwd")"
  done <<<"$rows"
}

snapshot_rows() {
  jq -r '.sessions[] | [.sessionId, .cwd, .name] | @tsv' "$SNAPSHOT"
}

# Emits: status<TAB>sessionId<TAB>cwd<TAB>name
# status is one of: open, running, no-transcript, no-cwd
restore_plan() {
  # Checked here rather than in snapshot_rows: a die() inside the process
  # substitution below would only kill that subshell, leaving an empty plan
  # that reads as "nothing to restore".
  [[ -f "$SNAPSHOT" ]] || die "no snapshot at $(pretty_path "$SNAPSHOT") — run 'claude-tabs save' first"

  local live
  live="$(live_session_ids)"

  local sid cwd name status
  while IFS=$'\t' read -r sid cwd name; do
    [[ -n "$sid" ]] || continue
    if grep -qxF "$sid" <<<"$live"; then
      status="running"
    elif [[ ! -d "$cwd" ]]; then
      status="no-cwd"
    elif ! transcript_exists "$sid"; then
      status="no-transcript"
    else
      status="open"
    fi
    printf '%s\t%s\t%s\t%s\n' "$status" "$sid" "$cwd" "$name"
  done < <(snapshot_rows)
}

cmd_list() {
  require jq

  echo "live sessions:"
  local rows pid sid cwd name
  rows="$(live_rows)"
  if [[ -z "$rows" ]]; then
    echo "  (none)"
  else
    while IFS=$'\t' read -r pid _ sid cwd name; do
      printf '  %-24s pid %-8s %s\n' "$name" "$pid" "$(pretty_path "$cwd")"
    done <<<"$rows"
  fi

  [[ -f "$SNAPSHOT" ]] || { echo; echo "no snapshot yet — run 'claude-tabs save'"; return 0; }

  echo
  echo "restore plan ($(pretty_path "$SNAPSHOT")):"
  local status
  while IFS=$'\t' read -r status sid cwd name; do
    printf '  %-14s %-24s %s\n' "$status" "$name" "$(pretty_path "$cwd")"
  done < <(restore_plan)
}

kdl_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

cmd_restore() {
  require jq
  require zellij

  local dry_run=0
  case "${1:-}" in
    --dry-run) dry_run=1 ;;
    "") ;;
    *) die "unknown option: $1" ;;
  esac

  local claude_bin
  claude_bin="$(command -v claude)" || die "claude is required but not on PATH"

  local plan
  plan="$(restore_plan)"

  local -a skipped=()
  local layout_body="" opened=0
  local status sid cwd name
  while IFS=$'\t' read -r status sid cwd name; do
    case "$status" in
      running)
        skipped+=("$(printf '  already running   %-24s %s' "$name" "$(pretty_path "$cwd")")")
        ;;
      no-cwd)
        skipped+=("$(printf '  missing cwd       %-24s %s' "$name" "$(pretty_path "$cwd")")")
        ;;
      no-transcript)
        skipped+=("$(printf '  no transcript     %-24s %s' "$name" "$sid")")
        ;;
      open)
        layout_body+="    tab name=\"$(kdl_escape "$name")\" cwd=\"$(kdl_escape "$cwd")\" {"$'\n'
        layout_body+="        pane command=\"$(kdl_escape "$claude_bin")\" {"$'\n'
        layout_body+="            args \"--resume\" \"$(kdl_escape "$sid")\""$'\n'
        layout_body+="        }"$'\n'
        layout_body+="    }"$'\n'
        opened=$((opened + 1))
        ;;
    esac
  done <<<"$plan"

  if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "skipping:"
    printf '%s\n' "${skipped[@]}"
    echo
  fi

  if [[ $opened -eq 0 ]]; then
    echo "nothing to restore"
    return 0
  fi

  local layout
  layout="$(mktemp --suffix=.kdl -t claude-tabs.XXXXXX)"
  printf 'layout {\n%s}\n' "$layout_body" > "$layout"

  if [[ $dry_run -eq 1 ]]; then
    echo "would open $opened tab(s) with layout $layout:"
    echo
    cat "$layout"
    return 0
  fi

  echo "opening $opened tab(s)"
  # zellij --layout adds tabs to the current session when inside one, and starts
  # a new session otherwise, so the same layout file serves both cases.
  if [[ -n "${ZELLIJ:-}" ]]; then
    exec zellij --layout "$layout"
  else
    exec zellij --session "$ZELLIJ_SESSION" --layout "$layout"
  fi
}

main() {
  case "${1:-}" in
    save) shift; cmd_save "$@" ;;
    list) shift; cmd_list "$@" ;;
    restore) shift; cmd_restore "$@" ;;
    -h|--help|help|"") usage ;;
    *) usage >&2; die "unknown command: $1" ;;
  esac
}

main "$@"
