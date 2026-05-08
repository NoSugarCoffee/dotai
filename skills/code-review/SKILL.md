---
name: code-review
description: Comprehensive code review - orchestrates focused sub-reviews for security, performance, architecture, maintainability, and coding standards. Full and multi-domain subsets run reviewers in parallel when the runtime allows. Precision over recall.
---

# Code Review

## Skill layout (file tree)

The **`code-review`** directory contains this `SKILL.md` and nested reviewers (`architecture-review/`, …), each with its own `SKILL.md`. Repo paths are `skills/code-review/<reviewer>/`. After `install.sh`, only `~/.cursor/skills/code-review` (and other tools’ skill roots) points at this tree — there is no separate top-level `~/.cursor/skills/architecture-review`; open `code-review/architecture-review/SKILL.md` instead.

```text
code-review/
├── SKILL.md                      Entry — workflow, routing, context, output (this file)
├── architecture-review/SKILL.md
├── security-review/SKILL.md
├── performance-review/SKILL.md
├── maintainability-review/SKILL.md
└── coding-standards-review/SKILL.md
```

## Document map

| Section | Use it for |
|---------|------------|
| [Purpose](#purpose) | Review goal / quality bar |
| [Workflow](#workflow) | Orchestration; W1 / W2; parallel reviewer dispatch |
| [Operating rules](#operating-rules) | Philosophy and exclusions |
| [Sub-skill routing](#sub-skill-routing) | User intent → sub-skill |
| [Project context](#project-context) | Infer stack & norms from the repo (brief) |
| [Output contract](#output-contract) | Finding Markdown + summary table |

## Purpose

Conduct a focused, high-signal code review as a senior engineer. **Precision over recall** — fewer high-confidence findings beat noisy lists that invite ignoring feedback.

## When to apply

- User asks for PR review, code review, audit of changes, or pre-merge checks.
- User names a domain (security, performance, architecture, maintainability, standards) or wants a full pass.

Do not substitute this skill for running the user’s formatter or compiler; exclusions are under [Operating rules](#operating-rules).

## Required inputs

**Gate — do not start reviewing until both are settled** (infer or confirm from the user’s message):

1. **Focus**
   - **Focused**: exactly **one** of Security, Performance, Architecture, Maintainability, Coding Standards → load only that nested `SKILL.md` (see [Sub-skill routing](#sub-skill-routing)).
   - **Subset**: user names **two or more** domains but **not** a full pass → parallelize **only** the matching reviewers, then consolidate (same merge rules as W2).
   - **Full**: all sub-skills in parallel, dedupe, sort by severity.
2. **Diff baseline branch** — default `main` if unstated.

If the user already implied both, confirm in one sentence (for example: “Focused security review against `main` — correct?”).

After the gate, follow [Workflow](#workflow).

## Workflow

Orchestration uses **only** this **`code-review`** skill definition. Nested paths such as [`architecture-review/SKILL.md`](architecture-review/SKILL.md) are **instructions to load inside the same invocation** (parallel with other reviewers when applicable), unless the user explicitly opens one path in isolation.

### Cross-references to sub-skills

- Dead code and bool traps: [`maintainability-review/SKILL.md`](maintainability-review/SKILL.md)
- Style, typing, error handling: [`coding-standards-review/SKILL.md`](coding-standards-review/SKILL.md)

### W1 — Focused review

| Step | Action |
|------|--------|
| 1 | Map the user’s domain to a sub-skill using [Sub-skill routing](#sub-skill-routing). |
| 2 | [Project context](#project-context): infer once from the repo. |
| 3 | Invoke **only** the matching sub-skill. |
| 4 | Present findings using [Output contract](#output-contract). |
| 5 | Do **not** add findings from other domains unless **critical**. |

### W2 — Full review

| Step | Action |
|------|--------|
| 1 | [Project context](#project-context) **once** — shared baseline for all reviewers. |
| 2 | **In parallel**, for each row in **Full mode — domain → sub-skill** ([below](#full-mode--domain--sub-skill)): open that subdirectory’s `SKILL.md`, apply against the **same** diff concurrently (parallel reads, subagents/tasks, batched tool calls). Kick off **all** reviewer passes together; avoid serial pipelines unless your runtime forbids overlap. |
| 3 | Deduplicate (same issue from multiple sub-skills). |
| 4 | Sort by severity: critical → high → medium → low. |
| 5 | Present consolidated findings using [Output contract](#output-contract). |

Gate **Subset** uses the **same parallel pattern** scoped to **only** the routed reviewers matching the requested domains.

### Parallel dispatch summary

| Mode | Parallelism |
|------|----------------|
| W1 Focused | One nested reviewer — serial is fine |
| Full (all domains) | All five reviewers **in parallel** |
| **Subset** (Gate) | Only the selected domains’ reviewers — **in parallel** |

## Operating rules

### Philosophy

- **Context over syntax**: Prefer “why” over surface “what”.
- **Risk-based depth**: Critical paths get depth; routine changes stay lighter.
- **Actionable feedback**: Each finding includes a concrete fix and rationale.
- **Conservative**: When in doubt, do not flag.

### Universal exclusions

**Never comment on:**

- Style, formatting, whitespace (linters).
- Basic syntax errors (static analysis).
- Minor stylistic preferences that do not affect behavior.
- Generic “best practices” that contradict project conventions.
- Import ordering.

**Ignore unless they cause functional harm:**

- Naming that matches existing project conventions.
- Comment volume or style (unless critical logic is unexplained).

## Sub-skill routing

Use the **folder name** under `code-review/` (not a separate top-level installed skill). Example: `architecture-review/SKILL.md` inside the `code-review` tree.

### Focused mode — trigger → sub-skill

| Trigger phrase (examples) | Sub-skill |
|---------------------------|-----------|
| security, vulnerabilities, auth | `security-review` |
| performance, speed, memory, queries | `performance-review` |
| architecture, design, coupling, API | `architecture-review` |
| maintainability, dead code, bool traps, readability | `maintainability-review` |
| coding standards, style, typing, error handling | `coding-standards-review` |

### Full mode — domain → sub-skill

| Domain | Sub-skill |
|--------|-----------|
| Security | `security-review` |
| Performance | `performance-review` |
| Architecture | `architecture-review` |
| Maintainability | `maintainability-review` |
| Coding Standards | `coding-standards-review` |

## Project context

Infer language, frameworks, tests, and lint/setup from the repository (manifests, lockfiles, config, `AGENTS.md` / `CONTRIBUTING.md` when present). **Prefer this project’s actual conventions** over generic defaults. Ask the user only when the tree is too sparse or ambiguous to tell.

## Output contract

Use **Markdown only** (no XML). Group findings by domain, then deliver the summary table.

### Per-finding block

```markdown
### 🔴/🟠/🟡/🔵 [SEVERITY] — [category] · `file:line`

**Issue:** One-sentence description of the specific problem.

**Impact:** What breaks or what an attacker can do if unfixed.

**Fix:** Concrete code-level suggestion.
```

### Severity key

| Emoji | Level | Meaning |
|-------|-------|---------|
| 🔴 | critical | Must fix before merge |
| 🟠 | high | Should fix before merge |
| 🟡 | medium | Fix in near term |
| 🔵 | low | Nice to have |

Use section headers: `## Security`, `## Performance`, `## Architecture`, `## Maintainability`, `## Coding Standards`.

### Summary table (end of review)

```markdown
## Review Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | N |
| 🟠 High | N |
| 🟡 Medium | N |
| 🔵 Low | N |
| **Total** | **N** |

**Verdict:** ✅ Approve / 🔁 Request Changes / 💬 Needs Discussion

**Overall:** One paragraph assessment.
```
