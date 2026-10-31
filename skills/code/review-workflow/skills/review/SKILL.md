---
name: review
description: Run a routine code review of local changes or a GitLab MR or GitHub PR. Publish comments when the request explicitly asks for remote output.
argument-hint: "[MR/PR URL | local changes | base..head] [post]"
disable-model-invocation: true
---

Read `${CLAUDE_PLUGIN_ROOT}/SKILL.md` and execute it with routine depth. Resolve the target and destination from the user's request and these arguments: $ARGUMENTS

Use `${CLAUDE_PLUGIN_ROOT}/references/routine.md` for the process. The plugin's `dotai-review:routine-reviewer` agent can perform the analysis and validation pass; the caller owns scope resolution, report rendering, and GitLab or GitHub publication. An explicit request for deep depth takes precedence over this entry point's default.
