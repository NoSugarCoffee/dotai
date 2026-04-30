#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(SCRIPT_DIR, "..");
const SKILLS_DIR = join(ROOT_DIR, "skills");

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

function addSkill(args) {
  const options = parseAddArgs(args);
  const tempDir = mkdtempSync(join(tmpdir(), "dotai-skills-"));
  const repoDir = join(tempDir, "repo");

  try {
    run("git", ["clone", "--depth", "1", options.repoUrl, repoDir], ROOT_DIR);

    const candidates = findSkillCandidates(repoDir);
    const selected = selectSkill(candidates, options.skillName);
    const targetName = slugify(selected.name);
    const targetDir = join(SKILLS_DIR, targetName);

    if (existsSync(targetDir) && !options.force) {
      throw new Error(`Skill already exists at ${relative(ROOT_DIR, targetDir)}. Re-run with --force to replace it.`);
    }

    if (existsSync(targetDir)) {
      rmSync(targetDir, { recursive: true, force: true });
    }

    mkdirSync(SKILLS_DIR, { recursive: true });
    cpSync(selected.dir, targetDir, { recursive: true, dereference: true });
    console.log(`Installed ${selected.name} to ${relative(ROOT_DIR, targetDir)}`);

    run("bash", [join(ROOT_DIR, "scripts", "install.sh")], ROOT_DIR);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

function parseAddArgs(args) {
  const repoUrl = args[0];
  let skillName = "";
  let force = false;

  if (repoUrl === undefined || repoUrl.startsWith("-")) {
    throw new Error("Missing repository URL.");
  }

  for (let index = 1; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === "--skill") {
      const value = args[index + 1];
      if (value === undefined || value.startsWith("-")) {
        throw new Error("Missing value for --skill.");
      }
      skillName = value;
      index += 1;
      continue;
    }

    if (arg === "--force") {
      force = true;
      continue;
    }

    throw new Error(`Unknown option: ${arg}`);
  }

  if (skillName.trim() === "") {
    throw new Error("Missing required --skill value.");
  }

  return {
    repoUrl,
    skillName,
    force,
  };
}

function findSkillCandidates(rootDir) {
  const skillFiles = findSkillFiles(rootDir);
  const candidates = skillFiles.map((skillFile) => {
    const dir = dirname(skillFile);
    const metadata = parseSkillMetadata(readFileSync(skillFile, "utf8"));
    const dirName = basename(dir);

    return {
      dir,
      name: metadata.name === "" ? dirName : metadata.name,
      dirName,
    };
  });

  if (candidates.length === 0) {
    throw new Error("No SKILL.md files were found in the repository.");
  }

  return candidates;
}

function findSkillFiles(rootDir) {
  const entries = readdirSync(rootDir, { withFileTypes: true });
  const results = [];

  for (const entry of entries) {
    const fullPath = join(rootDir, entry.name);

    if (entry.isDirectory()) {
      if (entry.name === ".git" || entry.name === "node_modules") {
        continue;
      }
      results.push(...findSkillFiles(fullPath));
      continue;
    }

    if (entry.isFile() && entry.name === "SKILL.md") {
      results.push(fullPath);
    }
  }

  return results;
}

function parseSkillMetadata(contents) {
  const metadata = {
    name: "",
  };

  if (!contents.startsWith("---\n")) {
    return metadata;
  }

  const endIndex = contents.indexOf("\n---", 4);
  if (endIndex === -1) {
    return metadata;
  }

  const frontmatter = contents.slice(4, endIndex);
  for (const line of frontmatter.split("\n")) {
    const match = line.match(/^name:\s*(.+)$/);
    if (match === null) {
      continue;
    }
    metadata.name = stripYamlString(match[1].trim());
  }

  return metadata;
}

function stripYamlString(value) {
  if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }

  return value;
}

function selectSkill(candidates, requestedName) {
  const requested = normalizeName(requestedName);
  const matches = candidates.filter((candidate) => {
    const names = [candidate.name, candidate.dirName, slugify(candidate.name), slugify(candidate.dirName)];
    return names.some((name) => normalizeName(name) === requested);
  });

  if (matches.length === 1) {
    return matches[0];
  }

  if (matches.length > 1) {
    throw new Error(`Multiple skills matched "${requestedName}": ${matches.map((match) => match.name).join(", ")}`);
  }

  const available = candidates.map((candidate) => candidate.name).sort().join(", ");
  throw new Error(`Skill "${requestedName}" was not found. Available skills: ${available}`);
}

function normalizeName(value) {
  return slugify(value).toLowerCase();
}

function slugify(value) {
  const slug = value
    .trim()
    .toLowerCase()
    .replace(/['"]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

  if (slug === "") {
    throw new Error(`Cannot create a skill directory name from "${value}".`);
  }

  return slug;
}

function run(command, args, cwd) {
  const result = spawnSync(command, args, {
    cwd,
    stdio: "inherit",
  });

  if (result.error !== undefined) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit code ${result.status}`);
  }
}

function printUsage() {
  console.log(`Usage:
  npx skills add <git-url> --skill <skill-name> [--force]

Example:
  npx skills add https://github.com/rknall/claude-skills --skill "SVG Logo Designer"`);
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  printUsage();
  process.exitCode = 1;
}
