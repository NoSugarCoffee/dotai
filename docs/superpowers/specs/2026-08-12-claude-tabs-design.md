# claude-tabs — Design Spec

**Date:** 2026-08-12
**Status:** Approved

## Problem

Several Claude Code sessions are typically open at once across different repos and worktrees.
When the terminal dies — a reboot, a closed window, a crashed emulator — every one of those
conversations has to be reopened by hand: remember which directories were in play, run
`claude --resume` in each, and pick the right conversation out of the interactive picker.
There is no single command that puts the set back.

## Goal

One command that restores the set of interactive Claude Code sessions that were open when
they were lost, each in its own zellij tab, in its own working directory, resumed in place.

## Source of truth — `~/.claude/sessions/`

Claude Code already maintains a live-session registry. Each running session writes
`~/.claude/sessions/<pid>.json`:

```json
{
  "pid": 38635,
  "sessionId": "e0b7eae3-f757-4b7a-8f49-fde95590ba7d",
  "cwd": "/home/liangliangdai/IdeaProjects/product-compass",
  "procStart": "90123",
  "kind": "interactive",
  "entrypoint": "cli",
  "name": "product-compass-44",
  "status": "busy",
  "startedAt": 1786541288281
}
```

No hook, no daemon, and no bookkeeping of our own is required: every field restore needs is
already there. The registry holds only live entries — Claude reaps dead ones — which is why
restoring reads a snapshot rather than the registry itself (see *Snapshot*).

### Qualifying entries

An entry is a restore candidate only if `kind == "interactive"` **and** `entrypoint == "cli"`.
This excludes background agents, `-p`/print runs, and SDK sessions, none of which correspond
to a terminal tab a human wants back.

### Liveness — why `procStart` is load-bearing

A session is running iff `/proc/<pid>` exists **and** its start time equals the recorded
`procStart`. `procStart` is field 22 of `/proc/<pid>/stat` (`starttime`, in clock ticks since
boot); this was verified against live sessions.

Checking `/proc/<pid>` alone is not sufficient. After a reboot the whole point is that the
recorded PIDs are gone, but PIDs are reused from a small space, so some unrelated process will
be sitting on them. A bare existence check would classify those sessions as "already running"
and silently skip exactly the sessions the user asked for. Comparing `procStart` makes a
recycled PID a miss rather than a false match.

Parsing note: `comm` in `/proc/<pid>/stat` is parenthesized and may itself contain spaces and
parentheses, so fields must be counted from the substring following the **last** `)`, where
`starttime` is field 20. Naive whitespace splitting of the whole line is wrong.

## Snapshot — `~/.claude/open-sessions.json`

`save` writes the qualifying live sessions to `~/.claude/open-sessions.json`:

```json
{
  "savedAt": 1786541928038,
  "sessions": [
    {
      "sessionId": "e0b7eae3-f757-4b7a-8f49-fde95590ba7d",
      "cwd": "/home/liangliangdai/IdeaProjects/product-compass",
      "name": "product-compass-44"
    }
  ]
}
```

Written atomically (temp file in the same directory, then `rename`) so an interrupted save
cannot leave a truncated snapshot that a later restore would silently read as a shorter list.

The snapshot exists because the live registry cannot answer the question after the fact: it
holds only sessions that are alive *now*, and the moment restore matters, none of them are.
Saving is explicit rather than hook-driven — the user chose to run it deliberately rather than
have every conversation turn write to disk.

## CLI

A single script, `scripts/claude-tabs.sh`, symlinked to `~/.local/bin/claude-tabs` by
`scripts/install.sh`.

### `claude-tabs save`

Snapshot qualifying live sessions and report what was captured:

```
$ claude-tabs save
saved 5 sessions to ~/.claude/open-sessions.json
  product-compass-86   ~/IdeaProjects/product-compass
  product-compass-2c   ~/IdeaProjects/product-compass
  ...
```

The session the command is run from is included — it is a tab like any other, and the user
wants it back too.

### `claude-tabs restore [--dry-run]`

Read the snapshot, drop any entry whose `sessionId` is currently live, open the remainder as
zellij tabs. `--dry-run` prints the plan and touches nothing.

Sessions are resumed **in place** (`claude --resume <id>`), not forked. Keeping the session ID
makes a second restore idempotent: the sessions from the first restore are live, so they are
skipped, rather than cloned into a second set of tabs.

### `claude-tabs list`

Show live sessions and what a restore would do. This is the command that makes the other two
inspectable, and the fastest way to confirm behaviour without opening anything.

## Restore mechanics — zellij

One single-tab layout is generated per session into a temp directory:

```kdl
layout {
    tab name="product-compass-44" cwd="/home/liangliangdai/IdeaProjects/product-compass" {
        pane command="claude" { args "--resume" "e0b7eae3-f757-4b7a-8f49-fde95590ba7d" }
    }
}
```

The launch path depends on context:

- **Inside zellij** (`$ZELLIJ` set) — loop `zellij action new-tab --layout <file>`, adding
  tabs to the current session.
- **Outside zellij** — build one multi-tab layout and
  `zellij --layout <file> --session claude-tabs`.

Using a layout rather than `new-tab` plus `write-chars` means the command is launched by
zellij directly, so nothing depends on shell startup timing or on characters being typed into
a pane that may not be ready.

## Failure behaviour

Following the repo's fail-fast rule — surface the problem, never paper over it:

- **No snapshot file** — explain that `save` has not been run, exit non-zero. Do not fall back
  to the live registry, which would restore something other than what was asked for.
- **Empty snapshot / everything already running** — say so and exit 0 without launching an
  empty zellij session.
- **Missing transcript** — a snapshot entry whose session `.jsonl` no longer exists under
  `~/.claude/projects/` is reported and skipped. Passing it to `claude --resume` would fail
  inside a freshly opened tab, where the user has to go hunting for the error.
- **Missing `cwd`** — a directory that no longer exists (a deleted worktree, a common case
  here) is reported and skipped rather than launched from a fallback directory, which would
  silently give the session the wrong project context.

## Non-goals

No hook and no daemon. No tmux path — zellij only. No cross-machine sync. No restoring
background agents or `-p` runs.

## Verification

Filesystem and process state only; no mocks.

1. `save` against the live sessions, then `list` and `restore --dry-run` must report the same
   count as candidates and zero to open, since all of them are still running.
2. End to end: start a throwaway session in a scratch directory, `save`, kill it, `restore`,
   and confirm the tab comes up with that conversation's history intact.
3. Liveness: confirm a snapshot entry whose PID has been reused is treated as not-running.
