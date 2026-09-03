---
name: spawn-session
description: Launch a new Claude Code session in a zellij tab on this machine, optionally with an initial prompt so it starts working immediately. Use when the user says "start a new claude session", "open a session in zellij", "拉起一个新的 claude session", "spawn a session to do X", "kick off a session for this", or wants work started in a separate session they will attach to later — typically from mobile, where there is no terminal to type into.
---

# Spawn a Claude session in zellij

Claude Code mobile cannot start a session on the PC, so from a phone there is no way to begin work.
This opens one as a zellij tab that keeps running — still there, with its scrollback, when you next
attach at your desk.

## Target a session explicitly

Always resolve a session name and pass `--session <name>`. That works from outside zellij *and* from
inside the named session, so there is one rule instead of an inside/outside branch:

```bash
zellij --session <name> action …
```

Inside zellij the name is already `$ZELLIJ_SESSION_NAME`. Otherwise list the live ones:

```bash
zellij list-sessions -n | grep -v EXITED | awk '{print $1}'
```

`-s` looks like the obvious flag but lists EXITED sessions too, so a name taken from it may be dead.

**Nothing alive?** Create a detached session first — no terminal needed, which is the whole point:

```bash
zellij attach --create-background <session>
```

Don't suggest opening a terminal instead.

## Create the tab

Read the existing tab names first, so you don't add a second tab the user cannot tell from the first:

```bash
zellij --session <name> action query-tab-names
zellij --session <name> action new-tab --name <tab> --cwd <abs-dir> \
  -- "$(command -v claude)" ["initial prompt"]
```

- `new-tab` prints the new tab's **id** on stdout; that plus exit 0 is your confirmation — no second
  query afterwards.
- **Resolve `claude` with `command -v`.** What follows `--` runs without a shell, so it does not
  inherit your login PATH.
- **`claude [prompt]` starts interactive *and* submits that prompt.** From a phone this is the
  payload: the session starts working instead of idling at an empty prompt.
- Prefer a tab to a pane — a tab gets full width and doesn't shrink the caller's. Use
  `zellij run -- claude` only when the user wants it side by side.

## Choose the cwd deliberately, then report back

Default to the project root and **say which you used**. Don't inherit the calling shell's cwd: after
other work it is often parked in a git worktree or a scratch dir. Ask only if the target is genuinely
ambiguous.

The requester cannot see the screen, so report the session, tab name, tab id, cwd, and the initial
prompt if you passed one — plus how to reach it: `zellij attach <session>`, then `Ctrl+t` and arrows.

## Never

- **Kill or delete sessions to tidy up.** `kill-session` / `delete-session` destroy someone's running
  work and its scrollback.
- **Resurrect an `EXITED` session unasked.** Attaching with `--force-run-commands` re-runs every
  command it had on startup.
