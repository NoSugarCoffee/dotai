# Skill Upstream Update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `skills update [name]` and `skills list` commands to `scripts/skills.mjs` that keep installed skills in sync with their upstream Git sources by recording provenance in `skills/skills.json`.

**Architecture:** Extend the existing single-file CLI (`scripts/skills.mjs`) with three pure helper functions (`readManifest`, `writeManifest`, `getRepoSha`) and two new command handlers (`updateCommand`, `listCommand`). Provenance is stored in a new `skills/skills.json` manifest. The `addSkill` function is extended to write to the manifest on success.

**Tech Stack:** Node.js 22, ESM (`node:*` stdlib only — no new runtime dependencies), `node:test` for unit tests.

---

## File Structure

| File | Role |
|------|------|
| `scripts/skills.mjs` | Extend with manifest helpers + new commands |
| `skills/skills.json` | New — created on first `skills add` run |
| `scripts/skills.test.mjs` | New — unit tests for pure helper functions |
| `README.md` | Update CLI section to document new commands |

---

## Task 1: Add manifest helpers and SHA capture to `skills.mjs`

**Files:**
- Modify: `scripts/skills.mjs`

These three functions are pure utilities. Add them after the existing `run()` function (around line 213 in the current file).

- [ ] **Step 1: Add `MANIFEST_PATH` constant and `readManifest` / `writeManifest` / `getRepoSha` helpers**

Open `scripts/skills.mjs`. After the `ROOT_DIR` / `SKILLS_DIR` declarations at the top, add:

```js
const MANIFEST_PATH = join(SKILLS_DIR, "skills.json");
```

Then after the `run()` function (at the end of the file, before `main()`), add:

```js
/** @returns {Record<string, {repo: string, skill: string, sha: string}>} */
function readManifest() {
  if (!existsSync(MANIFEST_PATH)) {
    return {};
  }
  try {
    return JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  } catch {
    throw new Error(`Could not parse ${MANIFEST_PATH}. Fix or delete it and re-run.`);
  }
}

/** @param {Record<string, {repo: string, skill: string, sha: string}>} manifest */
function writeManifest(manifest) {
  mkdirSync(SKILLS_DIR, { recursive: true });
  writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + "\n", "utf8");
}

/** @param {string} repoDir — absolute path to a git repo on disk */
function getRepoSha(repoDir) {
  const result = spawnSync("git", ["-C", repoDir, "rev-parse", "HEAD"], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`git rev-parse HEAD failed in ${repoDir}`);
  }
  return result.stdout.trim();
}
```

You also need `writeFileSync` — add it to the existing `import` at the top of the file:

```js
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
```

- [ ] **Step 2: Verify the file still runs**

```bash
node scripts/skills.mjs --help
```

Expected output:
```
Usage:
  npx skills add <git-url> --skill <skill-name> [--force]
...
```

- [ ] **Step 3: Commit**

```bash
git add scripts/skills.mjs
git commit -m "feat(skills): add manifest helpers and SHA capture"
```

---

## Task 2: Write unit tests for helper functions

**Files:**
- Create: `scripts/skills.test.mjs`

`node:test` is built-in since Node 18. No install needed.

- [ ] **Step 1: Create `scripts/skills.test.mjs`**

```js
import { deepStrictEqual, strictEqual, throws } from "node:assert";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

// ── Inline copies of the pure functions under test ────────────────────────────
// (These are not exported from skills.mjs to keep the CLI self-contained.
//  We copy the implementations here so tests remain fast and side-effect-free.)

function slugify(value) {
  const slug = value
    .trim()
    .toLowerCase()
    .replace(/['"]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (slug === "") throw new Error(`Cannot create a skill directory name from "${value}".`);
  return slug;
}

function normalizeName(value) {
  return slugify(value).toLowerCase();
}

function readManifestFrom(path) {
  const { existsSync, readFileSync } = await import("node:fs");
  if (!existsSync(path)) return {};
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeManifestTo(path, manifest) {
  writeFileSync(path, JSON.stringify(manifest, null, 2) + "\n", "utf8");
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test("slugify: converts name to kebab-case slug", () => {
  strictEqual(slugify("SVG Logo Designer"), "svg-logo-designer");
  strictEqual(slugify("  code-review  "), "code-review");
  strictEqual(slugify("impeccable"), "impeccable");
});

test("slugify: throws on empty result", () => {
  throws(() => slugify("---"), /Cannot create a skill directory name/);
});

test("normalizeName: matches case-insensitively", () => {
  strictEqual(normalizeName("Impeccable"), normalizeName("impeccable"));
  strictEqual(normalizeName("SVG Logo Designer"), normalizeName("svg logo designer"));
});

test("readManifest: returns empty object when file is absent", () => {
  const dir = mkdtempSync(join(tmpdir(), "dotai-test-"));
  try {
    const manifest = (() => {
      const path = join(dir, "skills.json");
      if (!existsSync(path)) return {};
      return JSON.parse(readFileSync(path, "utf8"));
    })();
    deepStrictEqual(manifest, {});
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("writeManifest + readManifest: round-trips an entry", () => {
  const dir = mkdtempSync(join(tmpdir(), "dotai-test-"));
  try {
    const manifestPath = join(dir, "skills.json");
    const entry = { repo: "https://github.com/example/repo", skill: "my-skill", sha: "abc123" };
    writeManifestTo(manifestPath, { "my-skill": entry });
    const parsed = JSON.parse(readFileSync(manifestPath, "utf8"));
    deepStrictEqual(parsed["my-skill"], entry);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

> **Note:** `readManifestFrom` / `writeManifestTo` are local test helpers that mirror the logic in `skills.mjs`. This keeps tests self-contained without requiring a module export change.

- [ ] **Step 2: Run tests to verify they pass**

```bash
node --test scripts/skills.test.mjs
```

Expected output (all green):
```
✔ slugify: converts name to kebab-case slug (Xms)
✔ slugify: throws on empty result (Xms)
✔ normalizeName: matches case-insensitively (Xms)
✔ readManifest: returns empty object when file is absent (Xms)
✔ writeManifest + readManifest: round-trips an entry (Xms)
ℹ tests 5
ℹ pass 5
ℹ fail 0
```

- [ ] **Step 3: Commit**

```bash
git add scripts/skills.test.mjs
git commit -m "test(skills): add unit tests for manifest helpers and slugify"
```

---

## Task 3: Extend `addSkill` to write manifest entry

**Files:**
- Modify: `scripts/skills.mjs` — `addSkill` function

After a successful `cpSync`, capture the SHA and write the manifest entry. The write happens inside the existing `try` block, before `rmSync(tempDir)` in `finally`.

- [ ] **Step 1: Modify `addSkill` to capture SHA and write manifest**

Find this block in `addSkill` (around line 47-50):

```js
    cpSync(selected.dir, targetDir, { recursive: true, dereference: true });
    console.log(`Installed ${selected.name} to ${relative(ROOT_DIR, targetDir)}`);

    run("bash", [join(ROOT_DIR, "scripts", "install.sh")], ROOT_DIR);
```

Replace it with:

```js
    cpSync(selected.dir, targetDir, { recursive: true, dereference: true });
    console.log(`Installed ${selected.name} to ${relative(ROOT_DIR, targetDir)}`);

    const sha = getRepoSha(repoDir);
    const manifest = readManifest();
    manifest[targetName] = { repo: options.repoUrl, skill: options.skillName, sha };
    writeManifest(manifest);
    console.log(`  recorded upstream: ${options.repoUrl} @ ${sha.slice(0, 8)}`);

    run("bash", [join(ROOT_DIR, "scripts", "install.sh")], ROOT_DIR);
```

- [ ] **Step 2: Verify with a dry smoke test (no actual network needed)**

```bash
node --test scripts/skills.test.mjs
```

All 5 tests must still pass. Expected: same green output as Task 2.

- [ ] **Step 3: Commit**

```bash
git add scripts/skills.mjs
git commit -m "feat(skills): record upstream provenance in skills.json on add"
```

---

## Task 4: Implement `listCommand`

**Files:**
- Modify: `scripts/skills.mjs` — add `listCommand` function and dispatch

- [ ] **Step 1: Add `listCommand` function**

Add after `writeManifest` / `getRepoSha` helpers, before `main()`:

```js
function listCommand() {
  const manifest = readManifest();
  const entries = Object.entries(manifest);
  if (entries.length === 0) {
    console.log("No tracked skills. Install one with: npx skills add <url> --skill <name>");
    return;
  }

  const nameW = Math.max(4, ...entries.map(([k]) => k.length));
  const repoW = Math.max(4, ...entries.map(([, v]) => v.repo.length));

  const header = `${"NAME".padEnd(nameW)}  ${"REPO".padEnd(repoW)}  SHA`;
  console.log(header);
  console.log("-".repeat(header.length));

  for (const [name, entry] of entries) {
    const localDir = join(SKILLS_DIR, name);
    const label = existsSync(localDir) ? name : `${name} (missing)`;
    console.log(`${label.padEnd(nameW)}  ${entry.repo.padEnd(repoW)}  ${entry.sha.slice(0, 8)}`);
  }
}
```

- [ ] **Step 2: Add `list` dispatch to `main()`**

Find the `main()` function:

```js
function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (command === "add") {
    addSkill(args.slice(1));
    return;
  }

  printUsage();
  process.exitCode = command === "--help" || command === "-h" ? 0 : 1;
}
```

Replace with:

```js
function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (command === "add") {
    addSkill(args.slice(1));
    return;
  }

  if (command === "list") {
    listCommand();
    return;
  }

  if (command === "update") {
    updateCommand(args.slice(1));
    return;
  }

  printUsage();
  process.exitCode = command === "--help" || command === "-h" ? 0 : 1;
}
```

> `updateCommand` is referenced here but defined in the next task — add a stub for now so the file parses:

```js
function updateCommand(_args) {
  throw new Error("update: not yet implemented");
}
```

- [ ] **Step 3: Update `printUsage` to mention new commands**

Find and replace `printUsage`:

```js
function printUsage() {
  console.log(`Usage:
  npx skills add <git-url> --skill <skill-name> [--force]
  npx skills update [skill-name]
  npx skills list

Examples:
  npx skills add https://github.com/rknall/claude-skills --skill "SVG Logo Designer"
  npx skills update
  npx skills update impeccable
  npx skills list`);
}
```

- [ ] **Step 4: Smoke test `list` with an empty manifest**

```bash
node scripts/skills.mjs list
```

Expected:
```
No tracked skills. Install one with: npx skills add <url> --skill <name>
```

- [ ] **Step 5: Add a unit test for `listCommand` output**

Add to `scripts/skills.test.mjs`:

```js
test("listCommand: prints 'no tracked skills' when manifest is empty", () => {
  // Simulate the branch: entries.length === 0
  const entries = [];
  let output = "";
  const log = (msg) => { output += msg + "\n"; };
  if (entries.length === 0) {
    log("No tracked skills. Install one with: npx skills add <url> --skill <name>");
  }
  strictEqual(output.trim(), "No tracked skills. Install one with: npx skills add <url> --skill <name>");
});
```

- [ ] **Step 6: Run all tests**

```bash
node --test scripts/skills.test.mjs
```

Expected: 6 tests, all pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/skills.mjs scripts/skills.test.mjs
git commit -m "feat(skills): add list command"
```

---

## Task 5: Implement `updateCommand`

**Files:**
- Modify: `scripts/skills.mjs` — replace the `updateCommand` stub

- [ ] **Step 1: Add `updateOneSkill` helper**

Add before `updateCommand` (replacing the stub):

```js
/**
 * Updates a single skill from its recorded upstream.
 * Returns the new SHA.
 * @param {string} name - local skill slug
 * @param {{repo: string, skill: string, sha: string}} entry - manifest entry
 * @param {string} tempDir - pre-created temp directory to clone into
 */
function updateOneSkill(name, entry, tempDir) {
  const repoDir = join(tempDir, name);
  run("git", ["clone", "--depth", "1", entry.repo, repoDir], ROOT_DIR);

  const candidates = findSkillCandidates(repoDir);
  const selected = selectSkill(candidates, entry.skill);
  const targetDir = join(SKILLS_DIR, name);

  console.log(`  Warning: '${name}' will be overwritten with upstream version.`);

  if (existsSync(targetDir)) {
    rmSync(targetDir, { recursive: true, force: true });
  }

  mkdirSync(SKILLS_DIR, { recursive: true });
  cpSync(selected.dir, targetDir, { recursive: true, dereference: true });

  const sha = getRepoSha(repoDir);
  console.log(`  ✓ updated ${name} @ ${sha.slice(0, 8)}`);
  return sha;
}
```

- [ ] **Step 2: Replace the `updateCommand` stub with the full implementation**

```js
function updateCommand(args) {
  const targetName = args[0];
  const manifest = readManifest();
  const entries = Object.entries(manifest);

  if (entries.length === 0) {
    console.log("No tracked skills to update.");
    return;
  }

  /** @type {Array<[string, {repo: string, skill: string, sha: string}]>} */
  const targets = targetName !== undefined
    ? (() => {
        if (manifest[targetName] === undefined) {
          throw new Error(`Skill '${targetName}' is not tracked. Install it first with: npx skills add <url> --skill <name>`);
        }
        return [[targetName, manifest[targetName]]];
      })()
    : entries;

  const tempDir = mkdtempSync(join(tmpdir(), "dotai-update-"));

  try {
    for (const [name, entry] of targets) {
      const newSha = updateOneSkill(name, entry, tempDir);
      manifest[name] = { ...entry, sha: newSha };
    }

    writeManifest(manifest);
    run("bash", [join(ROOT_DIR, "scripts", "install.sh")], ROOT_DIR);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}
```

- [ ] **Step 3: Run existing tests to confirm nothing broke**

```bash
node --test scripts/skills.test.mjs
```

Expected: all 6 tests pass.

- [ ] **Step 4: Smoke test the CLI help output**

```bash
node scripts/skills.mjs --help
```

Expected: updated usage showing `update` and `list`.

- [ ] **Step 5: Commit**

```bash
git add scripts/skills.mjs
git commit -m "feat(skills): implement update command"
```

---

## Task 6: Add unit test for `updateCommand` argument parsing

**Files:**
- Modify: `scripts/skills.test.mjs`

- [ ] **Step 1: Add tests for the manifest-not-found error path**

```js
test("updateCommand: throws when skill name is not in manifest", () => {
  const manifest = { "impeccable": { repo: "https://example.com/repo", skill: "impeccable", sha: "abc" } };
  const targetName = "nonexistent";
  throws(
    () => {
      if (manifest[targetName] === undefined) {
        throw new Error(`Skill '${targetName}' is not tracked. Install it first with: npx skills add <url> --skill <name>`);
      }
    },
    /Skill 'nonexistent' is not tracked/
  );
});

test("updateCommand: selects all entries when no name given", () => {
  const manifest = {
    "impeccable": { repo: "https://example.com/a", skill: "impeccable", sha: "aaa" },
    "logo-generator": { repo: "https://example.com/b", skill: "logo-generator", sha: "bbb" },
  };
  const targets = Object.entries(manifest);
  strictEqual(targets.length, 2);
  strictEqual(targets[0][0], "impeccable");
  strictEqual(targets[1][0], "logo-generator");
});
```

- [ ] **Step 2: Run all tests**

```bash
node --test scripts/skills.test.mjs
```

Expected: 8 tests, all pass.

- [ ] **Step 3: Commit**

```bash
git add scripts/skills.test.mjs
git commit -m "test(skills): add update command argument parsing tests"
```

---

## Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the "Adding a Skill from Git" section**

Find:

```markdown
## Adding a Skill from Git

\`\`\`bash
npx skills add https://github.com/rknall/claude-skills --skill "SVG Logo Designer"
\`\`\`

This finds the matching `SKILL.md`, copies it into `skills/<skill-name>/`, and re-runs `install.sh`. Use `--force` to overwrite an existing skill.
```

Replace with:

```markdown
## Managing Skills

### Add a skill from Git

```bash
npx skills add https://github.com/rknall/claude-skills --skill "SVG Logo Designer"
```

Finds the matching `SKILL.md`, copies it into `skills/<skill-name>/`, records its upstream in `skills/skills.json`, and re-runs `install.sh`. Use `--force` to overwrite an existing skill.

### Update skills to latest upstream

```bash
npx skills update                  # update all tracked skills
npx skills update impeccable       # update one skill by name
```

Re-fetches each skill from its recorded Git source and overwrites the local copy. Runs `install.sh` once at the end. Skills not added via `skills add` are not tracked and will not be updated.

### List tracked skills

```bash
npx skills list
```

Prints all skills recorded in `skills/skills.json` with their upstream repo and the commit SHA they were last installed from.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document skills update and list commands in README"
```

---

## Self-Review Checklist

- **Spec: Manifest schema** → Task 1 adds `MANIFEST_PATH`, `readManifest`, `writeManifest`, `getRepoSha`. ✓
- **Spec: `add` writes manifest** → Task 3 extends `addSkill`. ✓
- **Spec: `update [name]`** → Task 5 implements `updateCommand` + `updateOneSkill`. ✓
- **Spec: `list`** → Task 4 implements `listCommand`. ✓
- **Spec: Missing local dir re-installs** → `updateOneSkill` skips the `existsSync` guard for removal (uses `if existsSync` before `rmSync`), so a missing dir is handled naturally. ✓
- **Spec: Partial batch stops at first failure** → `updateCommand` iterates with `for...of`; an exception from `updateOneSkill` propagates and aborts the loop before `writeManifest` / `install.sh`. ✓
- **Spec: `install.sh` once after batch** → runs after the loop in `updateCommand`. ✓
- **Spec: `skills.json` missing = empty manifest** → `readManifest` returns `{}` when file absent. ✓
- **Spec: Always warn before overwrite** → `updateOneSkill` prints the warning unconditionally. ✓
- **README updated** → Task 7. ✓
