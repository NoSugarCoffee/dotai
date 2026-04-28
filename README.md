# dotai

Personal cross-tool AI agent configuration — rules, skills, hooks, and agents in one place.

## Rules (canonical source)

Authoritative rule text is **[`rules/coding.md`](rules/coding.md)** (code style, errors, typing, dependencies).

Edit `rules/coding.md`, then run **`bash scripts/install.sh`** to publish downstream.

## Where install copies things

- **Claude Code**: `~/.claude/rules/coding.md` → symlink to `rules/coding.md`.
- **Skills**: Symlinked from `skills/` to `~/.cursor/skills`, `~/.agents/skills`, `~/.copilot/skills`.

See [`AGENTS.md`](AGENTS.md) for tools that read repo-root agent instructions.
