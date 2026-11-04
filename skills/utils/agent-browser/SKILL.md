---
name: agent-browser
description: Use when driving a website with the agent-browser CLI — open a page, click, fill a form, extract text, screenshot, log in, or test a web app. Also use when reusing a logged-in Chrome profile, cookies, or storage, or when automation should leave the user's mouse and foreground tab alone.
---

# agent-browser

Browser automation from the shell. `snapshot` prints the page as an accessibility tree; each element has a ref such as `@e1`. Act on that ref, then snapshot again. The browser stays open between commands.

Adapted from the Apache-2.0 project [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) v0.41.2 (`d52a5e90c372ec4710c69adc3837ac14bbd852aa`): `README.md`, `skills/agent-browser/SKILL.md`, `skill-data/core`, and the [sessions](https://agent-browser.dev/sessions) and [CDP](https://agent-browser.dev/cdp-mode) docs. For a flag not shown here, run `agent-browser --help` or `agent-browser <command> --help`. The installed CLI serves a longer guide with `agent-browser skills get core`.

## Install

```bash
npm i -g agent-browser
# or: brew install agent-browser
# or: nix profile install nixpkgs#agent-browser   # nixpkgs lags the npm release
agent-browser install          # Chrome for Testing, first time
agent-browser install --with-deps   # Linux: also the browser's system libraries
```

The CLI prefers the Chrome for Testing cache from `agent-browser install`. When that cache is empty it falls back to a system Chrome, Chromium, or Brave (on Linux, the first of those names on `PATH`).

## The loop

Headless is the default (`headless` is on unless `--headed` or `AGENT_BROWSER_HEADED` is set). Pass `--headed` only when the user needs to see the window.

Every command below takes `--session`. Get one stable name and repeat it; a new shell drops `AGENT_BROWSER_SESSION`:

```bash
SESSION="$(agent-browser session id --scope worktree --prefix task)"
agent-browser --session "$SESSION" open <url>
agent-browser --session "$SESSION" snapshot
agent-browser --session "$SESSION" click @e1
agent-browser --session "$SESSION" snapshot
```

`snapshot -i` limits the tree to interactive elements. Output looks like:

```
- button "Continue" [ref=e1]
- textbox "Email" [ref=e2]
```

Act with the `@eN` form of that ref:

```bash
agent-browser --session "$SESSION" click @e1
agent-browser --session "$SESSION" fill @e2 "user@example.com"   # clear, then type
agent-browser --session "$SESSION" type @e2 "more"               # type, leave existing text
agent-browser --session "$SESSION" press Enter
```

The same pattern covers `dblclick`, `select`, `check`, `uncheck`, `hover`, `focus`, `upload`, `scroll`, and `drag`. `find role button click --name "Submit"` works without a prior snapshot. A CSS selector is the fallback.

Refs name elements from the snapshot that produced them. Elements that survive a same-document update keep their refs. Navigation, a replaced node, or a new document invalidates the refs that pointed at what went away, and a stale ref errors instead of hitting a different element. After a DOM change, snapshot again before the next action.

## Logged-in state

Use a copy of the login when that is enough.

**Chrome profile name.** `agent-browser profiles` lists directory and display names. `--profile Default` or `--profile "Work"` copies that Chrome, Chrome Canary, Chromium, or Brave profile to a temp directory and launches from the copy. The original profile stays unmodified, and the copy is deleted when the browser closes, so a login finished in that session is not written back. On Windows, quit Chrome first if it is already running.

**Persistent directory.** A path, `--profile ~/.myapp-profile`, is a profile of its own. Cookies, localStorage, IndexedDB, and the login survive later launches with the same path.

**Already-running Chrome.** `connect <port|url>` and `--cdp <port|url>` attach the session until `close`. Later commands in that session reuse the browser. `--cdp` takes a port or a `ws://` / `wss://` URL. `--auto-connect` discovers a Chrome that already exposes debugging.

```bash
agent-browser --session "$SESSION" connect 9222
agent-browser --session "$SESSION" --cdp 9222 snapshot
agent-browser --session "$SESSION" --auto-connect snapshot
```

`connect` and `--cdp` wait up to 2 seconds for the debugging port. If that browser goes away, later commands fail instead of launching a new one. `--auto-connect` reads Chrome's `DevToolsActivePort` file, then probes ports 9222 and 9229. Chrome 144+ asks the user to approve remote debugging on the first connection.

**Cookies and storage file.** `state save ./auth.json` writes cookies plus localStorage and sessionStorage. `--state ./auth.json` loads that file at launch; `state load ./auth.json` loads it into a browser that is already open. The file holds session tokens in plaintext. Keep it out of git.

**Automatic persistence.** `--restore` (no value uses the session name as the key) saves and reloads cookies and localStorage for that `--session`, on close and periodically. A session name on its own isolates the daemon and does not persist anything.

```bash
agent-browser --session "$SESSION" --auto-connect state save ./auth.json
agent-browser --session "$SESSION" --restore --state ./auth.json open https://app.example.com/dashboard
```

## Stay out of the user's way

`--session <name>` is a separate browser, with its own cookies, storage, history, and tabs. Names are Unicode letters and numbers, hyphens, and underscores. The unnamed default session is one browser shared with every other agent on the machine and it persists across conversations. `session id --scope worktree --prefix <task>` prints a name that stays the same for this checkout.

When several sessions share one Chrome over `--cdp` or `--auto-connect`, pass `--pin-tab` on the first command. The session sticks to its own tab. If that tab is closed, commands fail with `tab_gone` instead of acting on another tab. Recover with `tab new <url>` or `tab list`. `--no-pin-tab` turns a sticky pin off.

Clicks, fills, and keystrokes are CDP input (`Input.dispatchMouseEvent`, `Input.dispatchKeyEvent`). The page receives them. The operating-system cursor stays where it is.

Attaching to the user's own Chrome can still bring a tab forward. `tab new` opens a tab Chrome activates. `tab <id>` switches by the stable id from `tab` (such as `t2`) and sends `Page.bringToFront`. Auto-connect sends the same call when it opens a fresh tab. v0.41.2 does not expose a `bringtofront` command. Use a separate `--session`, or a `--profile` copy, when the user is working in that Chrome.

Close with `agent-browser --session "$SESSION" close` when the task is done.
