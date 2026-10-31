---
name: review
description: Run a routine code review of local changes or a GitLab merge request. Publish comments when the request explicitly asks for GitLab output.
argument-hint: "[GitLab MR URL | local changes | base..head] [post to GitLab]"
disable-model-invocation: true
---

Read `${CLAUDE_PLUGIN_ROOT}/SKILL.md` and execute it with routine depth. Resolve the target and destination from the user's request and these arguments: $ARGUMENTS

Use `${CLAUDE_PLUGIN_ROOT}/references/routine.md` for the process. The plugin's `dotai-review:routine-reviewer` agent can perform the analysis and validation pass; the caller owns scope resolution, report rendering, and GitLab publication. An explicit request for deep depth takes precedence over this entry point's default.
