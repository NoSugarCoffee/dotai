---
name: spawn-session
description: Launch a new Claude Code session in a zellij tab on this machine, optionally with an initial prompt so it starts working immediately. Use when the user says "start a new claude session", "open a session in zellij", "拉起一个新的 claude session", "spawn a session to do X", "kick off a session for this", or wants work started in a separate session they will attach to later — typically from mobile, where there is no terminal to type into.
---

# Spawn a Claude session in zellij

From a phone there is no terminal. This turns *"start a session working on X"* into one instruction:
the new session lands in a zellij tab that keeps running, so it is there — with its scrollback — when
you next attach at your desk.

## First decide: are you inside zellij?

Everything below depends on this, and getting it wrong is the main failure.

```bash
echo "${ZELLIJ:-not-in-zellij} / ${ZELLIJ_SESSION_NAME:-}"
```

- **Set** — `zellij action …` targets the session you are in.
- **Not set** (a mobile/cloud session, a cron run, a plain shell) — every command needs an explicit
  target: `zellij --session <name> action …`. This works fine from outside; it is not a limitation,
  just a required flag.

## Pick the target session — not with `list-sessions -s`

`-s` prints dead sessions alongside live ones (measured on this machine: 9 names listed, 7 actually
alive), so choosing from it can aim at a corpse and fail for reasons that look like a zellij bug.
Filter instead:

```bash
zellij list-sessions -n | grep -v EXITED | awk '{print $1}'
```

`-n` also marks the session you are in as `(current)`.

**Cold start — nothing alive.** Create a detached session first, then add the tab to it:

```bash
zellij attach --create-background <session>
```

Do not ask the user to "just open a terminal" — that is the exact thing they cannot do.

## Create the tab

```bash
zellij action new-tab --name <name> --cwd <abs-dir> -- /abs/path/to/claude ["initial prompt"]
```

- It prints the new tab's **id** on stdout. Keep it for the report.
- **Use an absolute path to `claude`.** The command runs without a shell, so it does not get your
  login shell's PATH. Resolve it first with `command -v claude`.
- **`claude [prompt]` starts interactive *and* submits that prompt.** This is the whole point for
  mobile — the spawned session begins the work instead of waiting at an empty prompt.
- **Prefer a tab over a pane.** A tab gets full width and does not shrink the caller's own pane. Use
  `zellij run -- claude` only when the user actually wants it side by side.

## Confirm, then report back concretely

The requester cannot see the screen, so an unverified "done" is worthless. Check the tab exists:

```bash
zellij action query-tab-names                      # inside
zellij --session <name> action query-tab-names     # outside
```

Then say: session name, tab name, tab id, cwd, and the initial prompt if you passed one. Add how to
reach it — `zellij attach <session>`, then `Ctrl+t` and arrows to switch tabs.

## Choose the cwd deliberately

A session opened in the wrong directory is the most common way this disappoints. Default to the
project/repo root and **say which you used**. In particular do not inherit the calling shell's cwd by
accident — after earlier work it is often parked in a git worktree or a scratch dir, which is rarely
where the next session should start. Ask only if the target is genuinely ambiguous.

## Never

- **Kill or delete sessions to tidy up.** `kill-session` / `delete-session` destroy someone's running
  work and its scrollback; they are not part of this task.
- **Resurrect an `EXITED` session unasked.** Attaching with `--force-run-commands` re-runs every
  command it had on startup.
- **Assume the tab name is unique.** Reusing a name makes two tabs the user cannot tell apart; add a
  short suffix when one already exists.
