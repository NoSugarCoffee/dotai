---
name: deep-review
description: Run independent architecture, quality, bug and security reviews followed by validation and severity audit. Supports local reports and explicitly requested GitLab or GitHub publication.
argument-hint: "[MR/PR URL | local changes | base..head] [post]"
disable-model-invocation: true
---

Read `${CLAUDE_PLUGIN_ROOT}/SKILL.md` and execute it with deep depth. Resolve the target and destination from the user's request and these arguments: $ARGUMENTS

Read `${CLAUDE_PLUGIN_ROOT}/references/deep.md`. Use `dotai-review:analysis-reviewer` for each specialist and `dotai-review:finding-validator` for validation and severity audit, supplying the role explicitly. The caller owns scope, finding state, report rendering, and publication.
