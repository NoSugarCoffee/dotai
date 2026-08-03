import { deepStrictEqual, strictEqual, throws } from "node:assert";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const CLIS_MJS = join(SCRIPT_DIR, "clis.mjs");
const MANIFEST_PATH = resolve(SCRIPT_DIR, "..", "clis.json");
const REQUIRED_FIELDS = ["purpose", "package", "binary", "install", "version", "check", "update"];

// ── Inline copies of the pure functions under test ────────────────────────────
// These mirror the implementations in clis.mjs.

function validateEntry(name, entry) {
  if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
    throw new Error(`CLI '${name}' must be an object with: ${REQUIRED_FIELDS.join(", ")}.`);
  }

  const missing = REQUIRED_FIELDS.filter((field) => typeof entry[field] !== "string" || entry[field].trim() === "");
  if (missing.length > 0) {
    throw new Error(`CLI '${name}' is missing required field(s): ${missing.join(", ")}.`);
  }
}

function parseVersion(output) {
  if (typeof output !== "string") return null;
  const match = output.match(/\d+\.\d+\.\d+[0-9A-Za-z.+-]*/);
  return match === null ? null : match[0];
}

function statusFor(installed, latest) {
  if (!installed.present) return "missing";
  if (installed.version === null) return "broken";
  if (latest === null) return "unknown";
  return installed.version === latest ? "current" : "outdated";
}

const VERSION_MANAGER_INSTALL_DIR =
  /\/(?:\.asdf|\.local\/share\/mise|\.local\/share\/rtx|\.rbenv|\.pyenv|\.nodenv)\/installs\//;

function globalPath(path) {
  return path
    .split(":")
    .filter((entry) => !VERSION_MANAGER_INSTALL_DIR.test(entry))
    .join(":");
}

const PINNED_RUNTIME_VARS = /^(?:npm_config_prefix|asdf_[a-z0-9_]+_version)$/i;

function withoutPinnedRuntime(env) {
  return Object.fromEntries(Object.entries(env).filter(([key]) => !PINNED_RUNTIME_VARS.test(key)));
}

function selectTargets(manifest, name) {
  const entries = Object.entries(manifest);

  if (name === undefined) {
    if (entries.length === 0) throw new Error("No CLIs tracked.");
    return entries;
  }

  if (manifest[name] === undefined) throw new Error(`CLI '${name}' is not tracked.`);
  return [[name, manifest[name]]];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test("parseVersion pulls the version out of CLI output", () => {
  strictEqual(parseVersion("0.7.90\n"), "0.7.90");
  strictEqual(parseVersion("hyperframes v1.2.3-beta.1"), "1.2.3-beta.1");
  strictEqual(parseVersion("no version here"), null);
  strictEqual(parseVersion(null), null);
});

test("statusFor distinguishes missing, broken, outdated, current and unknown", () => {
  strictEqual(statusFor({ present: false, version: null }, "0.7.90"), "missing");
  // A CLI on PATH that cannot report its version is installed against the wrong
  // runtime — that is a different failure from not being installed at all.
  strictEqual(statusFor({ present: true, version: null }, "0.7.90"), "broken");
  strictEqual(statusFor({ present: true, version: "0.7.90" }, null), "unknown");
  strictEqual(statusFor({ present: true, version: "0.7.89" }, "0.7.90"), "outdated");
  strictEqual(statusFor({ present: true, version: "0.7.90" }, "0.7.90"), "current");
});

test("globalPath drops version-manager install dirs and keeps shims", () => {
  const path = [
    "/home/u/.asdf/shims",
    "/home/u/.asdf/installs/nodejs/20.8.0/bin",
    "/home/u/.asdf/installs/nodejs/20.8.0/.npm/bin",
    "/home/u/.local/share/mise/installs/node/20.8.0/bin",
    "/usr/local/bin",
    "/opt/installs/bin",
  ].join(":");

  strictEqual(globalPath(path), "/home/u/.asdf/shims:/usr/local/bin:/opt/installs/bin");
  strictEqual(globalPath(""), "");
});

test("withoutPinnedRuntime drops the version manager's per-directory runtime vars", () => {
  const env = {
    PATH: "/usr/bin",
    NPM_CONFIG_PREFIX: "/home/u/.asdf/installs/nodejs/20.8.0/.npm",
    npm_config_prefix: "/home/u/.asdf/installs/nodejs/20.8.0/.npm",
    ASDF_NODEJS_VERSION: "20.8.0",
    ASDF_DIR: "/home/u/.asdf",
    NPM_CONFIG_REGISTRY: "https://example.test",
  };

  deepStrictEqual(withoutPinnedRuntime(env), {
    PATH: "/usr/bin",
    ASDF_DIR: "/home/u/.asdf",
    NPM_CONFIG_REGISTRY: "https://example.test",
  });
});

test("validateEntry rejects entries missing required fields", () => {
  throws(() => validateEntry("broken", { purpose: "x" }), /missing required field/);
  throws(() => validateEntry("broken", { ...fullEntry(), install: "  " }), /missing required field/);
  throws(() => validateEntry("broken", ["not", "an", "object"]), /must be an object/);
  validateEntry("ok", fullEntry());
});

test("selectTargets returns one entry by name and rejects unknown names", () => {
  const manifest = { alpha: fullEntry(), beta: fullEntry() };
  deepStrictEqual(selectTargets(manifest, "beta"), [["beta", manifest.beta]]);
  strictEqual(selectTargets(manifest, undefined).length, 2);
  throws(() => selectTargets(manifest, "gamma"), /not tracked/);
  throws(() => selectTargets({}, undefined), /No CLIs tracked/);
});

test("the committed clis.json satisfies the manifest contract", () => {
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  strictEqual(Object.keys(manifest).length > 0, true);
  for (const [name, entry] of Object.entries(manifest)) validateEntry(name, entry);
});

test("clis.mjs list prints the tracked CLIs", () => {
  const result = spawnSync(process.execPath, [CLIS_MJS, "list"], { encoding: "utf8" });
  strictEqual(result.status, 0);
  strictEqual(result.stdout.includes("hyperframes"), true);
});

test("clis.mjs rejects an unknown subcommand", () => {
  const result = spawnSync(process.execPath, [CLIS_MJS, "bogus"], { encoding: "utf8" });
  strictEqual(result.status, 1);
  strictEqual(result.stdout.includes("Usage:"), true);
});

function fullEntry() {
  return {
    purpose: "p",
    package: "pkg",
    binary: "bin",
    install: "install",
    version: "version",
    check: "check",
    update: "update",
  };
}
