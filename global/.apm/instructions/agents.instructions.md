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

- Sign in to sites yourself rather than handing the browser back. Fill any username, password, 动态码 / itoken / OTP or custom vault field on an ego-browser page with the `utils.credential-fill` skill. Never run `bw get`, `op read` or `op item get --reveal` yourself: their output is the secret.
- The store is whichever of 1Password (`OP_SERVICE_ACCOUNT_TOKEN`, vault `agent`) or Bitwarden (`BW_SESSION`, whole vault) `~/.zshrc-local` exports; a machine sets up one. If neither exists, point the user to "Agent credentials" in the dotai README; don't set it up yourself.
- The login is the one whose URL hostname, then path, matches the page. If the skill reports no match or a tie, ask the user to fix the vault rather than trying candidates: failed attempts can lock the account.
- Prefer a dedicated login skill where one exists (e.g. `internal.cas-login`).
