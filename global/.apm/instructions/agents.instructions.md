---
description: Global agent workflow rules for every project
---

## Merge requests and pull requests

- Open every MR/PR with **squash commits** and **delete source branch** enabled.
  - GitLab push: `-o merge_request.squash -o merge_request.remove_source_branch`.
  - `idev-cli code mr create --squash --remove-source-branch`.
  - `glab mr create --squash-before-merge --remove-source-branch`.
  - GitHub: merge with `gh pr merge --squash --delete-branch`.

## Tool preferences

- Prefer Ego Lite (`ego-browser` skill) for browser automation when it is available.
- Use Orca Automations for cron jobs and recurring scheduled tasks.
