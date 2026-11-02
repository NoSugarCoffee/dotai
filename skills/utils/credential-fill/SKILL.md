---
name: credential-fill
description: Use whenever an ego-browser page asks for a credential — username, password, a 动态码 / itoken / OTP / TOTP, or a custom vault field — on any site, including Captain WebConsole, jumpserver and CAS. Fills the field straight from the machine's password store (1Password or Bitwarden) without the value ever entering your context, so never run `bw get`, `op read` or `op item get --reveal` yourself, and never hand a login or OTP prompt back to the user.
---

# Credential fill

```bash
python3 ~/.claude/skills/utils.credential-fill/scripts/credential_fill.py \
  --space <task space id or name> --page <page label> \
  --selector '<css selector of the input>' \
  --field username|password|totp|custom:<name> [--submit '<button selector>']
```

It prints only `filled <field> from '<item>' into <selector> on <host>`, plus `, then clicked <submit>` with
`--submit`.

- **The login is picked from the page's own URL.** Hostname first; on a tie, the item whose URL path
  also matches. No match exits 2 naming the host; a remaining tie exits 2 naming the candidates. Fix the vault (add the
  page's URL to the right item); don't retry with another item.
- **Host and path are checked just before typing, and again before a `--submit` click**, so a page that
  navigated away, even to another login page on the same host, is not filled or not submitted.
- **One field per call.** For username then password, call twice; then click submit yourself.
- **A TOTP expires in about 30 seconds.** Fill it with `--submit '<selector of the submit button>'`, which
  clicks in the same browser call. A code submitted later is usually rejected.
- The store comes from the calling environment, or from `~/.zshrc-local` when neither key is set:
  `OP_SERVICE_ACCOUNT_TOKEN` (vault `agent`) or `BW_SESSION` (whole vault). A machine sets up one; if
  both are set, 1Password is used.

Not covered: passkeys (a WebAuthn ceremony, not a value), SMS or email codes, and captchas. Those
need the user.
