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

## Credentials

- Sign in to sites yourself rather than handing the browser back. Read credentials only through these prompt-free stores. Their keys are exported from `~/.zshrc-local`, which you source if your shell lacks them:
  1. 1Password: `op` with `OP_SERVICE_ACCOUNT_TOKEN`, a read-only service account on vault `agent`.
  2. Bitwarden: `bw` with `BW_SESSION`, using only items in folder `agent`.
- Never call `op` without the service-account token. It falls back to the desktop app, which prompts the user.
- Use the one login whose URL hostname equals the login page's hostname. If none or several match, ask. Never try candidates, because failed attempts can lock the account.
- Never print a secret. Pipe it straight to whatever consumes it.
- Prefer a dedicated login skill where one exists (e.g. `internal.cas-login`).
