#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(SCRIPT_DIR, "..");
const MANIFEST_PATH = join(ROOT_DIR, "clis.json");
// These are global tools, so they must not inherit this repo's pinned toolchain:
// dotai pins an older Node than some CLIs require. Running from $HOME is not enough —
// a version manager exports the resolved install into the environment (PATH entries and
// NPM_CONFIG_PREFIX), and those outlive any directory change. Dropping them lets the
// shims re-resolve against $HOME, so a global install lands on the global runtime.
const RUN_DIR = homedir();
const VERSION_MANAGER_INSTALL_DIR =
  /\/(?:\.asdf|\.local\/share\/mise|\.local\/share\/rtx|\.rbenv|\.pyenv|\.nodenv)\/installs\//;
const PINNED_RUNTIME_VARS = /^(?:npm_config_prefix|asdf_[a-z0-9_]+_version)$/i;
const REQUIRED_FIELDS = ["purpose", "package", "binary", "install", "version", "check", "update"];
const STATUS_LABEL = {
  missing: "✗ not installed",
  broken: "✗ installed but not runnable",
  outdated: "! update available",
  current: "✓ current",
  unknown: "? latest version unknown",
};

function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (command === "list") {
    listCommand();
    return;
  }

  if (command === "check") {
    checkCommand(args.slice(1));
    return;
  }

  if (command === "install") {
    installCommand(args.slice(1));
    return;
  }

  if (command === "update") {
    updateCommand(args.slice(1));
    return;
  }

  printUsage();
  process.exitCode = command === "--help" || command === "-h" ? 0 : 1;
}

/**
 * @returns {Record<string, {purpose: string, package: string, binary: string, install: string, version: string, check: string, update: string}>}
 */
function readManifest() {
  if (!existsSync(MANIFEST_PATH)) {
    throw new Error(`No CLI manifest at ${MANIFEST_PATH}.`);
  }

  let parsed;
  try {
    parsed = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  } catch {
    throw new Error(`Could not parse ${MANIFEST_PATH}. Fix the JSON and re-run.`);
  }

  for (const [name, entry] of Object.entries(parsed)) {
    validateEntry(name, entry);
  }

  return parsed;
}

function validateEntry(name, entry) {
  if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
    throw new Error(`CLI '${name}' must be an object with: ${REQUIRED_FIELDS.join(", ")}.`);
  }

  const missing = REQUIRED_FIELDS.filter((field) => typeof entry[field] !== "string" || entry[field].trim() === "");
  if (missing.length > 0) {
    throw new Error(`CLI '${name}' is missing required field(s): ${missing.join(", ")}.`);
  }
}

/**
 * Selects the manifest entries a command operates on.
 * @param {Record<string, object>} manifest
 * @param {string | undefined} name
 */
function selectTargets(manifest, name) {
  const entries = Object.entries(manifest);

  if (name === undefined) {
    if (entries.length === 0) {
      throw new Error(`No CLIs tracked. Add one to ${MANIFEST_PATH}.`);
    }
    return entries;
  }

  if (manifest[name] === undefined) {
    const known = entries.map(([key]) => key).join(", ");
    throw new Error(`CLI '${name}' is not tracked. Known: ${known || "(none)"}.`);
  }

  return [[name, manifest[name]]];
}

/** Drops version-manager install directories so shims re-resolve outside this repo. */
function globalPath(path) {
  return path
    .split(":")
    .filter((entry) => !VERSION_MANAGER_INSTALL_DIR.test(entry))
    .join(":");
}

/** Strips the variables a version manager exports for the current directory's runtime. */
function withoutPinnedRuntime(env) {
  return Object.fromEntries(Object.entries(env).filter(([key]) => !PINNED_RUNTIME_VARS.test(key)));
}

function globalEnv() {
  return {
    ...withoutPinnedRuntime(process.env),
    PATH: globalPath(process.env.PATH ?? ""),
    PWD: RUN_DIR,
  };
}

/** Runs a shell command, streaming its output. Returns the exit code. */
function runStreamed(command) {
  const result = spawnSync(command, { cwd: RUN_DIR, env: globalEnv(), shell: true, stdio: "inherit" });
  if (result.error) throw result.error;
  return result.status ?? 1;
}

/**
 * Runs a shell command quietly.
 * @returns {{ok: boolean, output: string}}
 */
function runCaptured(command) {
  const result = spawnSync(command, { cwd: RUN_DIR, env: globalEnv(), shell: true, encoding: "utf8" });
  if (result.error) return { ok: false, output: result.error.message };
  return { ok: result.status === 0, output: `${result.stdout ?? ""}${result.stderr ?? ""}`.trim() };
}

function isOnPath(binary) {
  return spawnSync(`command -v ${binary}`, { cwd: RUN_DIR, env: globalEnv(), shell: true, stdio: "ignore" }).status === 0;
}

/** Extracts the first semver-looking token from CLI output. */
function parseVersion(output) {
  if (typeof output !== "string") return null;
  const match = output.match(/\d+\.\d+\.\d+[0-9A-Za-z.+-]*/);
  return match === null ? null : match[0];
}

/**
 * @param {{present: boolean, version: string | null}} installed
 * @param {string | null} latest
 * @returns {"missing" | "broken" | "current" | "outdated" | "unknown"}
 */
function statusFor(installed, latest) {
  if (!installed.present) return "missing";
  if (installed.version === null) return "broken";
  if (latest === null) return "unknown";
  return installed.version === latest ? "current" : "outdated";
}

/**
 * @returns {{present: boolean, version: string | null, error: string}}
 */
function installedVersion(entry) {
  if (!isOnPath(entry.binary)) return { present: false, version: null, error: "" };

  const result = runCaptured(entry.version);
  const version = result.ok ? parseVersion(result.output) : null;
  return { present: true, version, error: version === null ? result.output : "" };
}

function latestVersion(entry) {
  const result = runCaptured(`npm view ${entry.package} version`);
  return result.ok ? parseVersion(result.output) : null;
}

function printTable(header, rows) {
  const widths = header.map((label, column) =>
    Math.max(label.length, ...rows.map((row) => row[column].length)),
  );
  const line = (cells) => cells.map((cell, column) => cell.padEnd(widths[column])).join("  ").trimEnd();

  console.log(line(header));
  console.log("-".repeat(line(header).length));
  for (const row of rows) console.log(line(row));
}

function listCommand() {
  const manifest = readManifest();
  const rows = Object.entries(manifest).map(([name, entry]) => [name, entry.package, entry.purpose]);

  if (rows.length === 0) {
    console.log(`No CLIs tracked. Add one to ${MANIFEST_PATH}.`);
    return;
  }

  printTable(["NAME", "PACKAGE", "PURPOSE"], rows);
}

function checkCommand(args) {
  const manifest = readManifest();
  const targets = selectTargets(manifest, args[0]);

  const results = targets.map(([name, entry]) => {
    const installed = installedVersion(entry);
    const latest = installed.present ? latestVersion(entry) : null;
    return { name, entry, installed, latest, status: statusFor(installed, latest) };
  });

  printTable(
    ["NAME", "INSTALLED", "LATEST", "STATUS"],
    results.map((result) => [
      result.name,
      result.installed.version ?? "—",
      result.latest ?? "—",
      STATUS_LABEL[result.status],
    ]),
  );

  let actionNeeded = results.some((result) => result.status !== "current");

  for (const broken of results.filter((result) => result.status === "broken")) {
    console.log(`\n✗ ${broken.name}: '${broken.entry.version}' failed —\n${broken.installed.error}`);
  }

  for (const result of results.filter((candidate) => candidate.status !== "missing" && candidate.status !== "broken")) {
    console.log(`\n→ ${result.name}: ${result.entry.check}`);
    if (runStreamed(result.entry.check) !== 0) actionNeeded = true;
  }

  if (actionNeeded) {
    console.log(`\nRun 'node scripts/clis.mjs update' to reconcile.`);
    process.exitCode = 1;
  }
}

function installCommand(args) {
  const force = args.includes("--force");
  const name = args.find((arg) => !arg.startsWith("-"));
  const manifest = readManifest();
  const targets = selectTargets(manifest, name);

  for (const [cliName, entry] of targets) {
    const installed = installedVersion(entry);

    // A binary on PATH that cannot report its version is reinstalled, not skipped:
    // a shim left behind by a version manager looks installed and runs nothing.
    if (installed.version !== null && !force) {
      console.log(`  ✓ ${cliName} already installed (${installed.version})`);
      continue;
    }

    console.log(`  → installing ${cliName}: ${entry.install}`);
    if (runStreamed(entry.install) !== 0) {
      throw new Error(`Install failed for '${cliName}': ${entry.install}`);
    }
    verifyRunnable(cliName, entry);
  }
}

function updateCommand(args) {
  const name = args.find((arg) => !arg.startsWith("-"));
  const manifest = readManifest();
  const targets = selectTargets(manifest, name);

  for (const [cliName, entry] of targets) {
    console.log(`  → updating ${cliName}: ${entry.update}`);
    if (runStreamed(entry.update) !== 0) {
      throw new Error(`Update failed for '${cliName}': ${entry.update}`);
    }
    verifyRunnable(cliName, entry);
  }
}

// A global npm install under a shim-based version manager (asdf, mise) writes the
// binary without creating its shim, so the freshly installed CLI stays off PATH.
function verifyRunnable(name, entry) {
  const installed = installedVersion(entry);

  if (!installed.present) {
    throw new Error(
      `'${entry.binary}' is not on PATH after installing ${name}. ` +
        `Using asdf or mise? Run 'asdf reshim nodejs' (or 'mise reshim'), then re-run this command.`,
    );
  }

  if (installed.version === null) {
    throw new Error(`${name} installed but '${entry.version}' failed:\n${installed.error}`);
  }

  console.log(`  ✓ ${name} ${installed.version}`);
}

function printUsage() {
  console.log(`Usage:
  node scripts/clis.mjs list                 # show tracked CLIs
  node scripts/clis.mjs check [name]         # compare installed vs latest, then run each CLI's own check
  node scripts/clis.mjs install [name] [--force]
  node scripts/clis.mjs update [name]

Tracked CLIs live in clis.json. install.sh installs any that are missing.
Set DOTAI_SKIP_CLIS=1 to skip the CLI step during install.sh.`);
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  printUsage();
  process.exitCode = 1;
}
