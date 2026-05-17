# Skill Upstream Update — Design Spec

**Date:** 2026-05-17
**Status:** Approved

## Problem

Skills are copied from external Git repositories into `skills/` with no record of their origin.
Once installed, there is no way to pull in upstream improvements without manually repeating the
`skills add` command and knowing the original URL.

## Goal

Add an `update` command (and supporting infrastructure) to `scripts/skills.mjs` so that any
skill installed via `skills add` can be refreshed to the latest upstream commit with a single
command.

## Manifest — `skills/skills.json`

A new file, written and read exclusively by `skills.mjs`, tracks every skill installed through
the CLI.

### Schema

```json
{
  "<local-slug>": {
    "repo": "<git-clone-url>",
    "skill": "<skill-name-matched-in-repo>",
    "sha": "<full-commit-sha-at-install-time>"
  }
}
```

- **Key** — the local directory slug (`skills/<key>/`), produced by `slugify()`.
- **`repo`** — the URL passed to `git clone`.
- **`skill`** — the `--skill` value used to select the skill inside the repo.
- **`sha`** — the full commit SHA of the repo at copy time, recorded for drift detection.

### Lifecycle

- `skills add` writes/overwrites the entry on success.
- `skills update` reads the entry, re-clones, overwrites the local dir, and updates `sha`.
- No entry is written if an operation fails (write only on success).
- Skills added manually (without the CLI) have no entry and are silently ignored by `update`.

---

## CLI Commands

### `skills add <url> --skill <name> [--force]` (extended)

Behaviour is unchanged externally. New side-effect: after a successful copy, write or update the
manifest entry for the installed skill.

### `skills update [name]`

Re-fetches one or all tracked skills from their recorded upstream.

**Without `name`** — iterates every key in `skills.json` and updates each in turn.
**With `name`** — updates that single skill only.

Per-skill steps:
1. Read the manifest entry; fail with a clear error if `name` is not found.
2. Shallow-clone the recorded `repo` to a temp dir.
3. Locate the skill inside the clone using the recorded `skill` value (same logic as `add`).
4. Remove the existing local skill dir and copy the freshly cloned version in its place.
5. Update `sha` in the manifest.

Post-batch:
- Run `install.sh` **once** after all skills have been updated successfully (not per skill).
- If any single skill fails, stop immediately, report the failure, skip `install.sh`.
  Already-updated skills in the batch remain in place.

**Missing local dir**: if the manifest has an entry but the local dir is absent, treat it as a
fresh install (re-create the dir).

### `skills list`

Prints a formatted table of all manifest entries. Read-only — no network calls.

```
NAME             REPO                                           SHA
impeccable       https://github.com/pbakaus/impeccable          a1b2c3d4
logo-generator   https://github.com/op7418/logo-generator-skill e5f6a7b8
```

A `(missing)` marker is appended to the name if the local dir does not exist on disk.

---

## Error Handling

| Situation | Behaviour |
|-----------|-----------|
| `update <name>` not in manifest | Hard error: "Skill '<name>' is not tracked. Install it first with `skills add`." |
| `git clone` fails during update | Propagate exit-code error; no manifest write; stop batch. |
| Partial batch failure | Stop at first failure; report which skill failed; do not run `install.sh`. |
| Local edits since install (`sha` differs) | Print a warning before overwriting: "Warning: local changes in '<name>' will be overwritten." Continue without prompting (update always replaces). |
| `skills.json` missing or empty | Treat as empty manifest; `update` with no args prints "No tracked skills." |

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/skills.mjs` | Add `readManifest`, `writeManifest`, `updateSkill`, `listSkills` functions; extend `addSkill` to write manifest; add `update` and `list` command dispatch. |
| `skills/skills.json` | New file, created on first `skills add` run. |
| `README.md` | Update CLI usage section to document `update` and `list` commands. |

---

## Out of Scope

- Network check in `skills list` (no upstream SHA comparison — update always re-clones).
- Interactive conflict resolution for locally modified skill files.
- Tracking skills that were not installed via this CLI.
