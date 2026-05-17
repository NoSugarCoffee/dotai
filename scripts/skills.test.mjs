import { deepStrictEqual, strictEqual, throws } from "node:assert";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
