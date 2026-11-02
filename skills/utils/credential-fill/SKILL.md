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

It prints only `filled <field> from '<item>' into <selector> on <host>`.

- **The login is picked from the page's own URL.** Hostname first; on a tie, the item whose URL path
  also matches. No match or a remaining tie exits 2 and names the candidates. Fix the vault (add the
  page's URL to the right item); don't retry with another item.
- **The host is checked again just before typing**, so a page that navigated away gets nothing.
- **One field per call.** For username then password, call twice; then click submit yourself.
- **A TOTP expires in about 30 seconds.** Fill it with `--submit '<selector of the submit button>'`, which
  clicks in the same browser call. A separate click a minute later fails with "check_otp_code failed".
- The store is whichever key `~/.zshrc-local` exports: `OP_SERVICE_ACCOUNT_TOKEN` (vault `agent`) or
  `BW_SESSION` (whole vault).

Not covered: passkeys (a WebAuthn ceremony, not a value), SMS or email codes, and captchas. Those
need the user.
