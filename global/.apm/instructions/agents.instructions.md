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

- Sign in to sites yourself rather than handing the browser back. Read credentials only from the one store set up on this machine, 1Password or Bitwarden: whichever key `~/.zshrc-local` exports. Source that file if your shell lacks the key. If neither key exists, point the user to "Agent credentials" in the dotai README; don't set it up yourself.
- Use the one login whose URL hostname equals the login page's hostname. If several match, take the one whose URL path also matches. If none or still several, ask. Never try candidates, because failed attempts can lock the account.
- An OTP / 动态码 / itoken prompt takes the TOTP of the login that same rule picks. Fill it yourself like a password; it is never a reason to hand back.
- Never print a secret. List items as id, name and URLs only, then read the one value you need and pipe it straight to whatever consumes it.
- Prefer a dedicated login skill where one exists (e.g. `internal.cas-login`).

### 1Password

- `op` with `OP_SERVICE_ACCOUNT_TOKEN`, a read-only service account on vault `agent`. Never call `op` without the token: it falls back to the desktop app, which prompts the user.
- Find: `op item list --vault agent --format json | jq '[.[] | {id, title, urls: [.urls[]?.href]}]'`. Read: `op read "op://agent/<id>/password"`, or `op item get <id> --otp`.

### Bitwarden

- `bw` with `BW_SESSION`, which opens the whole vault. Logins stay wherever they are.
- Find: `bw list items --search <host> | jq '[.[] | {id, name, uris: [.login.uris[]?.uri]}]'`. The projection is not optional: raw `bw list items` prints every match's decrypted password and TOTP seed. Read: `bw get password <id>`, or `bw get totp <id>`.
