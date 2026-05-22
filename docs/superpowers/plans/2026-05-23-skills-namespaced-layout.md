# Skills Namespaced Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize `dotai/skills/` from a flat list into category subdirectories and update `install.sh` to symlink them as `{category}:{skill-name}`, mirroring the `superpowers:` namespace pattern.

**Architecture:** Skills move into four category subdirs (`code/`, `docs/`, `creative/`, `utils/`). `install.sh`'s `link_skills` iterates two levels deep and builds `{category}:{skill}` symlink names. `skills.json` keys and `skill` fields are updated to match.

**Tech Stack:** Bash, git

---

### Task 1: Write verification script

A test script that will FAIL against the current flat layout and PASS after the reorganization is complete.

**Files:**
- Create: `scripts/verify-skills-layout.sh`

- [ ] **Step 1: Create the verification script**

```bash
#!/usr/bin/env bash
# Verifies that ~/.claude/skills/ contains namespaced symlinks from this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"
SKILLS_SRC="$ROOT/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

EXPECTED=(
  "code:diagnose"
  "code:code-review"
  "code:improve-codebase-architecture"
  "code:impeccable"
  "docs:grill-with-docs"
  "docs:handoff"
  "docs:project-readme-author"
  "creative:logo-generator"
  "creative:project-logo-author"
  "creative:hyperframes"
  "utils:baoyu-translate"
  "utils:skill-creator"
)

FLAT_SHOULD_NOT_EXIST=(
  "diagnose"
  "code-review"
  "improve-codebase-architecture"
  "impeccable"
  "grill-with-docs"
  "handoff"
  "project-readme-author"
  "logo-generator"
  "project-logo-author"
  "hyperframes"
  "baoyu-translate"
  "skill-creator"
)

PASS=0
FAIL=0

for name in "${EXPECTED[@]}"; do
  if [[ -L "$CLAUDE_SKILLS_DIR/$name" ]]; then
    echo "  ✓ $name"
    ((PASS++))
  else
    echo "  ✗ MISSING: $name"
    ((FAIL++))
  fi
done

for name in "${FLAT_SHOULD_NOT_EXIST[@]}"; do
  if [[ -L "$CLAUDE_SKILLS_DIR/$name" ]]; then
    # Check it resolves into THIS repo (not an unrelated skill)
    resolved="$(realpath "$CLAUDE_SKILLS_DIR/$name" 2>/dev/null || true)"
    if [[ "$resolved" == "$SKILLS_SRC"/* ]]; then
      echo "  ✗ STALE FLAT SYMLINK: $name"
      ((FAIL++))
    fi
  fi
done

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ All $PASS checks passed."
  exit 0
else
  echo "❌ $FAIL checks failed, $PASS passed."
  exit 1
fi
```

Save to `scripts/verify-skills-layout.sh` and make it executable:

```bash
chmod +x scripts/verify-skills-layout.sh
```

- [ ] **Step 2: Run it — expect failure (flat symlinks exist, namespaced ones don't)**

```bash
bash scripts/verify-skills-layout.sh
```

Expected: `❌ 24 checks failed, 0 passed.` (12 namespaced symlinks missing + 12 stale flat symlinks present)

- [ ] **Step 3: Commit the test**

```bash
git add scripts/verify-skills-layout.sh
git commit -m "test: add skills layout verification script"
```

---

### Task 2: Create category subdirectories and move skills

**Files:**
- Modify: `skills/` tree (git mv each skill into its category subdir)

Skill → category mapping:

| Skill | Category |
|-------|----------|
| `diagnose` | `code` |
| `code-review` | `code` |
| `improve-codebase-architecture` | `code` |
| `impeccable` | `code` |
| `grill-with-docs` | `docs` |
| `handoff` | `docs` |
| `project-readme-author` | `docs` |
| `logo-generator` | `creative` |
| `project-logo-author` | `creative` |
| `hyperframes` | `creative` |
| `baoyu-translate` | `utils` |
| `skill-creator` | `utils` |

- [ ] **Step 1: Create category directories**

```bash
mkdir -p skills/code skills/docs skills/creative skills/utils
```

- [ ] **Step 2: Move code skills**

```bash
git mv skills/diagnose skills/code/diagnose
git mv skills/code-review skills/code/code-review
git mv skills/improve-codebase-architecture skills/code/improve-codebase-architecture
git mv skills/impeccable skills/code/impeccable
```

- [ ] **Step 3: Move docs skills**

```bash
git mv skills/grill-with-docs skills/docs/grill-with-docs
git mv skills/handoff skills/docs/handoff
git mv skills/project-readme-author skills/docs/project-readme-author
```

- [ ] **Step 4: Move creative skills**

```bash
git mv skills/logo-generator skills/creative/logo-generator
git mv skills/project-logo-author skills/creative/project-logo-author
git mv skills/hyperframes skills/creative/hyperframes
```

- [ ] **Step 5: Move utils skills**

```bash
git mv skills/baoyu-translate skills/utils/baoyu-translate
git mv skills/skill-creator skills/utils/skill-creator
```

- [ ] **Step 6: Verify tree looks correct**

```bash
find skills -mindepth 1 -maxdepth 2 -type d | sort
```

Expected output:
```
skills/code
skills/code/code-review
skills/code/diagnose
skills/code/impeccable
skills/code/improve-codebase-architecture
skills/creative
skills/creative/hyperframes
skills/creative/logo-generator
skills/creative/project-logo-author
skills/docs
skills/docs/grill-with-docs
skills/docs/handoff
skills/docs/project-readme-author
skills/utils
skills/utils/baoyu-translate
skills/utils/skill-creator
```

- [ ] **Step 7: Commit the move**

```bash
git add -A skills/
git commit -m "refactor(skills): reorganize into code/docs/creative/utils categories"
```

---

### Task 3: Update install.sh

**Files:**
- Modify: `scripts/install.sh` lines 45–60 (the `link_skills` function)

- [ ] **Step 1: Replace the `link_skills` function body**

The current function (lines 46–61):
```bash
link_skills() {
  local target_dir="$1"
  local abs_skills
  abs_skills="$(cd "$SKILLS_SRC" && pwd -P)"

  mkdir -p "$target_dir"
  prune_symlinks_into_skills_dir "$target_dir" "$abs_skills"

  for skill_dir in "$SKILLS_SRC"/*/; do
    local skill_name
    skill_name="$(basename "$skill_dir")"
    rm -rf "${target_dir:?}/$skill_name"
    ln -sfn "$skill_dir" "$target_dir/$skill_name"
    echo "  ✓ skill: $skill_name → $target_dir/$skill_name"
  done
}
```

Replace with:
```bash
link_skills() {
  local target_dir="$1"
  local abs_skills
  abs_skills="$(cd "$SKILLS_SRC" && pwd -P)"

  mkdir -p "$target_dir"
  prune_symlinks_into_skills_dir "$target_dir" "$abs_skills"

  for category_dir in "$SKILLS_SRC"/*/; do
    local category
    category="$(basename "$category_dir")"
    for skill_dir in "$category_dir"*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name link_name
      skill_name="$(basename "$skill_dir")"
      link_name="${category}:${skill_name}"
      rm -rf "${target_dir:?}/$link_name"
      ln -sfn "$skill_dir" "$target_dir/$link_name"
      echo "  ✓ skill: $link_name → $target_dir/$link_name"
    done
  done
}
```

- [ ] **Step 2: Run install.sh**

```bash
bash scripts/install.sh
```

Expected output includes lines like:
```
→ Claude Code
  ✓ prune diagnose
  ✓ prune code-review
  ...
  ✓ skill: code:diagnose → /home/<user>/.claude/skills/code:diagnose
  ✓ skill: code:code-review → /home/<user>/.claude/skills/code:code-review
  ...
✅ dotai installed.
```

- [ ] **Step 3: Run verification script — expect pass**

```bash
bash scripts/verify-skills-layout.sh
```

Expected: `✅ All 12 checks passed.`

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat(install): link skills with category:name namespace"
```

---

### Task 4: Update skills.json

**Files:**
- Modify: `skills/skills.json`

- [ ] **Step 1: Replace the contents of `skills/skills.json`**

```json
{
  "code:diagnose": {
    "repo": "https://github.com/mattpocock/skills",
    "skill": "code/diagnose",
    "sha": "b8be62ffacb0118fa3eaa29a0923c87c8c11985c"
  },
  "code:improve-codebase-architecture": {
    "repo": "https://github.com/mattpocock/skills",
    "skill": "code/improve-codebase-architecture",
    "sha": "b8be62ffacb0118fa3eaa29a0923c87c8c11985c"
  },
  "code:impeccable": {
    "repo": "https://github.com/pbakaus/impeccable",
    "skill": "code/impeccable",
    "sha": "4af581e23f17d112d8f9d6b7a5b7ff37823494e1"
  },
  "docs:grill-with-docs": {
    "repo": "https://github.com/mattpocock/skills",
    "skill": "docs/grill-with-docs",
    "sha": "b8be62ffacb0118fa3eaa29a0923c87c8c11985c"
  },
  "docs:project-readme-author": {
    "repo": "https://github.com/tsilva/claudeskillz",
    "skill": "docs/project-readme-author",
    "sha": "d0470890caeb54268f0aa2917b35646ecea5d7b1"
  },
  "creative:hyperframes": {
    "repo": "https://github.com/heygen-com/hyperframes",
    "skill": "creative/hyperframes",
    "sha": "b30fd296950ef394e9ae5415e4db705e1751915c"
  },
  "creative:logo-generator": {
    "repo": "https://github.com/op7418/logo-generator-skill",
    "skill": "creative/logo-generator",
    "sha": "bf4e9ac4d4428bda261afcfe981871ceb92d94e6"
  },
  "creative:project-logo-author": {
    "repo": "https://github.com/tsilva/claudeskillz",
    "skill": "creative/project-logo-author",
    "sha": "d0470890caeb54268f0aa2917b35646ecea5d7b1"
  },
  "utils:baoyu-translate": {
    "repo": "https://github.com/JimLiu/baoyu-skills",
    "skill": "utils/baoyu-translate",
    "sha": "38cc497748bc8e32da84a8097bee1361234ce4dd"
  },
  "utils:skill-creator": {
    "repo": "https://github.com/anthropics/skills",
    "skill": "utils/skill-creator",
    "sha": "f458cee31a7577a47ba0c9a101976fa599385174"
  }
}
```

Note: `code:code-review`, `docs:handoff` are custom skills with no external repo — they are intentionally absent from `skills.json`.

- [ ] **Step 2: Verify JSON is valid**

```bash
python3 -m json.tool skills/skills.json > /dev/null && echo "✓ valid JSON"
```

Expected: `✓ valid JSON`

- [ ] **Step 3: Commit**

```bash
git add skills/skills.json
git commit -m "chore(skills): update skills.json keys and paths for namespaced layout"
```

---

### Task 5: Final smoke test

- [ ] **Step 1: Verify the full installed layout**

```bash
ls ~/.claude/skills/ | grep -E '^(code|docs|creative|utils):' | sort
```

Expected (12 lines):
```
code:code-review
code:diagnose
code:impeccable
code:improve-codebase-architecture
creative:hyperframes
creative:logo-generator
creative:project-logo-author
docs:grill-with-docs
docs:handoff
docs:project-readme-author
utils:baoyu-translate
utils:skill-creator
```

- [ ] **Step 2: Verify no stale flat repo symlinks remain**

```bash
ROOT="$(git rev-parse --show-toplevel)"
for name in diagnose code-review impeccable improve-codebase-architecture \
            grill-with-docs handoff project-readme-author \
            logo-generator project-logo-author hyperframes \
            baoyu-translate skill-creator; do
  link="$HOME/.claude/skills/$name"
  if [[ -L "$link" ]]; then
    resolved="$(realpath "$link" 2>/dev/null)"
    if [[ "$resolved" == "$ROOT"/* ]]; then
      echo "✗ stale: $name"
    fi
  fi
done
echo "✓ stale check done"
```

Expected: only `✓ stale check done` (no `✗` lines).

- [ ] **Step 3: Run verification script one final time**

```bash
bash scripts/verify-skills-layout.sh
```

Expected: `✅ All 12 checks passed.`
