---
name: review
description: Run a routine code review of local changes or a GitLab MR or GitHub PR. Publish comments when the request explicitly asks for remote output.
argument-hint: "[MR/PR URL | local changes | base..head] [post]"
disable-model-invocation: true
---

Read `${CLAUDE_PLUGIN_ROOT}/SKILL.md`. Resolve target and destination from the user's request and these arguments: $ARGUMENTS

Select routine depth unless the user explicitly requests deep depth. For routine depth, read `${CLAUDE_PLUGIN_ROOT}/references/routine.md` and delegate analysis and self-validation to `dotai-review:routine-reviewer`. For deep depth, read `${CLAUDE_PLUGIN_ROOT}/references/deep.md` and follow its independent worker pipeline. The caller owns scope resolution, report rendering, and publication for either depth.
