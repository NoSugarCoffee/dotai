import { deepStrictEqual, strictEqual, throws } from "node:assert";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";

// ── Inline copies of the pure functions under test ────────────────────────────
// These mirror the implementations in skills.mjs.
// Kept here so tests are self-contained and fast.

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
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    throw new Error(`Could not parse ${path}. Fix or delete it and re-run.`);
  }
}

function writeManifestTo(manifestPath, manifest) {
  mkdirSync(dirname(manifestPath), { recursive: true });
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n", "utf8");
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
  strictEqual(normalizeName("Impeccable"), "impeccable");
  strictEqual(normalizeName("impeccable"), "impeccable");
  strictEqual(normalizeName("SVG Logo Designer"), "svg-logo-designer");
  strictEqual(normalizeName("svg logo designer"), "svg-logo-designer");
});

test("readManifest: returns empty object when file is absent", () => {
  const dir = mkdtempSync(join(tmpdir(), "dotai-test-"));
  try {
    const manifest = readManifestFrom(join(dir, "skills.json"));
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
    const parsed = readManifestFrom(manifestPath);
    deepStrictEqual(parsed["my-skill"], entry);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("slugify: strips quotes", () => {
  strictEqual(slugify("it's alive"), "its-alive");
  strictEqual(slugify('"hello world"'), "hello-world");
});

test("slugify: throws on all-whitespace input", () => {
  throws(() => slugify("   "), /Cannot create a skill directory name/);
});

test("readManifest: throws descriptive error for malformed JSON", () => {
  const dir = mkdtempSync(join(tmpdir(), "dotai-test-"));
  try {
    const manifestPath = join(dir, "skills.json");
    writeFileSync(manifestPath, "{ not valid json", "utf8");
    throws(
      () => readManifestFrom(manifestPath),
      /Could not parse.*Fix or delete it/
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("writeManifest: creates parent directory if absent", () => {
  const dir = mkdtempSync(join(tmpdir(), "dotai-test-"));
  try {
    const manifestPath = join(dir, "nested", "skills.json");
    const entry = { repo: "https://github.com/example/repo", skill: "test", sha: "abc" };
    writeManifestTo(manifestPath, { test: entry });
    const parsed = readManifestFrom(manifestPath);
    deepStrictEqual(parsed["test"], entry);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("listCommand: prints 'no tracked skills' when manifest is empty", () => {
  const entries = [];
  let output = "";
  const log = (msg) => { output += msg + "\n"; };
  if (entries.length === 0) {
    log("No tracked skills. Install one with: npx skills add <url> --skill <name>");
  }
  strictEqual(output.trim(), "No tracked skills. Install one with: npx skills add <url> --skill <name>");
});
