---
name: project-readme-author
description: Create, modify, validate, and optimize README.md files following GitHub best practices.
license: MIT
compatibility: Any environment
argument-hint: "[create|modify|validate|optimize] [path]"
disable-model-invocation: false
user-invocable: true
metadata:
  author: tsilva
  version: "2.6.1"
---

# README Author

Create READMEs that hook readers in 5 seconds, prove value in 30 seconds, and enable success in under 10 minutes.

## Operations

| Operation | Triggers | Purpose |
|-----------|----------|---------|
| **create** | No README exists, "create/generate README" | Build from scratch |
| **modify** | README exists, "update/change README" | Preserve structure, update sections |
| **validate** | "check/review/audit README" | Score against best practices |
| **optimize** | "improve/enhance README" | Fix issues, enhance quality |

### Operation Detection

Use the deterministic operation selector:

```bash
uv run shared/select_operation.py --skill project-readme-author --args "$ARGUMENTS" --check-files "README.md"
```

**Fallback rules (if script unavailable):**
1. Check `$ARGUMENTS` for explicit operation keywords
2. Check if README.md exists at target path
3. Default: `create` if no README, `modify` if README exists

---

## Create Operation

Use when building a README from scratch. Follow the Core Framework and Workflow sections below.

**Mandatory pre-draft checklist:**
- [ ] Archive status checked — `.archived.md` exists? If yes, archive notice goes first
- [ ] Aha moment identified — "What's the most impressive single thing?"
- [ ] Tagline crafted with emoji(s)
- [ ] At least one quantified metric (if available)
- [ ] Appropriate CTA tier determined

## Modify Operation

Use when updating an existing README while preserving its structure.

- **Keep custom prose** — user-written descriptions, explanations, context
- **Update dynamic content** — versions, badge URLs, install commands
- **Respect markers** — content within `<!-- custom -->...<!-- /custom -->` is never touched
- **Preserve section order** — don't reorder unless explicitly requested
- **Preserve manual notes** — any hand-written note, warning, tip that's factually relevant
- **Default to preservation** — when relevance is unclear, use AskUserQuestion to confirm
- **Never assume obsolescence** — only remove when explicitly asked or factually incorrect
- **Archive notice sync** — if `.archived.md` exists, ensure notice is present and current; if removed, remove the notice
- **Deprecated sections** — ask user via AskUserQuestion before removing

**When in doubt, preserve existing content and use AskUserQuestion to confirm before removing anything.**

## Validate Operation

Score an existing README against best practices. Run Essential → Professional → Elite → **Virality** checklists plus project-type specifics. See [references/validation-guide.md](references/validation-guide.md) for scoring format, tiers, project-type checks, and checklists.

**Scoring weights:** Essential 40%, Professional 25%, Elite 15%, Virality 20%

## Optimize Operation

**Quick Wins (auto-apply):** Center hero, add alt text, fix badge URLs, add TOC if >500 words, standardize badge style, fix heading hierarchy, add emojis to headers, add archive notice if `.archived.md` exists and notice is missing.

**Virality Quick Wins (auto-apply):**
- Add star badge if stars > 100
- Add download badge if downloads > 1000/week
- Format existing stats as quotable block

**Requires Approval:** Add new sections, rewrite tagline, change badge selection, remove emojis, restructure content order.

**Virality Suggestions (require approval):**
- Add curiosity hook to hero
- Restructure overview as pain point narrative
- Create comparison table vs alternatives
- Add tiered CTAs

---

## Core Framework: Hook → Prove → Enable → Extend

| Phase | Time | Purpose | Elements | Virality Trigger |
|-------|------|---------|----------|------------------|
| **Hook** | 0-3 sec | Instant recognition | Logo + badges + one-liner + demo visual | Curiosity gap + visual impact |
| **Prove** | 3-30 sec | Build credibility | Social proof, features, trust signals | Social proof + comparison wins |
| **Enable** | 30 sec - 5 min | Immediate success | One-liner install + working example | "I can do this" moment |
| **Extend** | Committed users | Deep engagement | Docs links, contributing, API reference | Share triggers + community |

**The goal: Time to first success under 10 minutes.** The first 5-10 lines visible without scrolling determine whether users stay or leave.

## Aha Moment Visualization

The "aha moment" is the single most impressive demonstration of your project's value. It must answer "What does this DO?" within 3 seconds.

### 3-Second Rule

The first visual element after the tagline must show transformation — before → action → after.

### Aha Patterns by Project Type

| Type | Aha Format | Example |
|------|------------|---------|
| **CLI** | Terminal GIF: before → command → after | ripgrep searching 1M files in 0.2s |
| **Library** | 3-line code with commented "wow" output | `# 50 lines → 3 lines` |
| **AI/ML** | Benchmark comparison chart | "2x faster than GPT-3" |
| **Web App** | GIF of core interaction loop | One-click deploy animation |

### Requirements

- **Show transformation** — what changes from input to output
- **Max 5 seconds** — attention drops sharply after this
- **Loop seamlessly** — GIFs should restart without jarring cuts
- **Placement** — immediately after tagline, before any text

### Identifying the Aha Moment

Ask: "What's the most impressive single thing this project does?" Then visualize it.

## Logo Generation (Mandatory)

Every README must have a logo:

1. **Check for existing logo** — look for `logo.png` at repo root; if found, skip to README generation
2. **Generate if missing** — invoke the **project-logo-author** skill
3. **Determine display size** — use `mcp__image-tools__get_image_metadata` to get width, then divide by 2 for retina display (e.g., 1024px → `width="512"`)

## Hero Section

The hero section must be center-aligned with these elements in order:

### Title Rule

**The title must be exactly the repository name.** Preserve original casing — `my-awesome-tool` stays `my-awesome-tool`, not "My Awesome Tool".

```markdown
<div align="center">
  <img src="logo.png" alt="Project Name" width="{DISPLAY_WIDTH}"/>

  [![Build](badge)](link) [![Version](badge)](link) [![License](badge)](link)

  **A clear, catchy one-liner that explains what this does and why it matters**

  [Documentation](url) · [Demo](url) · [Discord](url)
</div>
```

### Curiosity Hook (Optional)

A bold line placed after badges, before tagline, to create an information gap:

| Type | Example |
|------|---------|
| **Question** | "Ever spent 2 hours debugging what this fixes in 10 seconds?" |
| **Stat** | "Used by 50,000+ developers worldwide" |
| **Comparison** | "10x faster than grep for code search" |
| **Challenge** | "Find any file in your repo under 100ms" |

**Rules:**
- Must be verifiable (don't exaggerate)
- Connects to a real pain point
- Creates desire to learn more

### Hero Elements

| Element | Specification |
|---------|---------------|
| Logo | Width = half actual pixels (for retina), centered |
| Badges | 3-6 maximum, shields.io for consistency |
| Curiosity hook | Optional bold line creating information gap |
| Tagline | One sentence with emoji(s), max 350 chars (fits GitHub "About" field) |
| Quick links | Docs, demo, community (if available) |

### Tagline Rules

**The tagline is THE hook** — the single most critical line in your README. Users decide to stay or leave based on this one sentence. It must be short, witty, and instantly communicate what the project does.

**Bookend Emoji Pattern:**
- One emoji at START, one emoji at END
- Creates visual framing that draws the eye
- Reinforces the message from both sides

**Requirements:**
- **Max 350 characters** — ideal 80-150 chars, punchy and scannable
- **Instantly clear** — reader must understand what project does from this line alone
- **Source from pyproject.toml** — if `description` field exists, use as base and enhance. If crafting new, sync back.

**Great taglines (bookend pattern):**
- ✅ `🚀 Build production-ready APIs in minutes, not hours ⚡`
- ✅ `🔍 Find anything in your codebase instantly 🎯`
- ✅ `🎨 Turn designs into code with one command 💻`
- ✅ `🔧 Magnificent app which corrects your previous console command ✨`

**Anti-patterns:**
- ❌ "A Python library for doing Y" — no emojis, too generic
- ❌ "⚡ Fast and easy to use" — vague, doesn't explain what it does
- ❌ "Tool for developers" — meaningless, could be anything
- ❌ "🚀 🔥 ⚡ Super awesome project 💪 🎉" — emoji spam, no substance

### GIF Demo Placement

For CLI tools, place an animated GIF demo **immediately after the tagline**.

## Archive Notice

If `.archived.md` exists at repo root, place this block as the absolute first README element (before hero `<div align="center">`):

```markdown
> [!WARNING]
> ## Archived
> This project is archived and no longer maintained.
>
> {rewritten .archived.md content}
```

Read `.archived.md` and rewrite its content to match the README's tone and style — clear, concise, well-formatted prose. Preserve all factual information (reasons, alternatives, migration paths) but do not copy the raw text literally. Adapt structure, phrasing, and formatting to feel native to the README.

Replace existing notice (never duplicate). Remove notice when `.archived.md` is absent.

## Pain Point Narrative

Structure the Overview section using Problem-Solution-Result pattern for emotional connection:

```markdown
**The Pain:** [1-2 sentences describing the frustration users face]

**The Solution:** [What this project does differently]

**The Result:** [Quantifiable outcome — time saved, lines reduced, speed gained]
```

### Before/After Format (Alternative)

| Before | After |
|--------|-------|
| 50 lines of boilerplate | 3-line function call |
| 2 hours debugging | 10-second fix |
| Manual deployments | One-click CI/CD |

## Social Proof Hierarchy

Ordered by impact (include what you have):

1. **Quantified Trust Signals**
   ```markdown
   > **50,000+** downloads | **4,000+** stars | **500+** contributors
   ```

2. **Authority Endorsements**
   ```markdown
   > "This tool is incredible. Saved us 10 hours/week."
   > — [@notable_person](link), CTO at Company
   ```

3. **"Used By" Logos** — 6-12 recognizable company logos

4. **Community Size** — Discord badge with member count

**Rules:**
- Always quantify (not "many users" but "50,000+ users")
- Verify all claims
- Update quarterly

## Tiered CTA System

Provide multiple engagement paths from low to high commitment:

| Level | Action | Example |
|-------|--------|---------|
| 1. **Try** | Quick Start | `npx create-myapp` or `pip install myapp` |
| 2. **Learn** | Documentation | "[Read the docs](link) (5 min read)" |
| 3. **Connect** | Community | "Questions? [Join our Discord](link)" |
| 4. **Support** | Star | "Useful? [Give us a star](link) ⭐" |
| 5. **Contribute** | PR | "[Good first issues](link)" |

Include at least 3 tiers. Place primary CTA (Try) prominently; others in appropriate sections.

## Shareable Elements

Elements designed to be screenshot and shared:

### Quotable Stats Block

```markdown
<div align="center">

| Metric | Value |
|--------|-------|
| ⚡ Speed | 10x faster than alternatives |
| 📦 Size | 2MB (no dependencies) |
| 🔧 Setup | 30 seconds |

</div>
```

### Comparison Tables

Fair benchmarks against alternatives:

| Tool | Speed | Memory | Features |
|------|-------|--------|----------|
| **This project** | 0.2s | 50MB | ✅ All |
| Alternative A | 2.1s | 200MB | ⚠️ Partial |
| Alternative B | 1.5s | 150MB | ❌ Missing |

**Rules:** Use equivalent configurations, link to benchmark methodology, update when alternatives improve.

### Social Preview

Remind users to configure GitHub's social preview image (Settings → Social preview):
- Size: 1280x640px
- Include: Logo, tagline, key metric
- This appears when the repo is shared on social media

## Badges

Use 4-7 badges in priority order: Build/CI → Coverage → Version → License → Downloads → Community.

For badge implementation details and code, see [references/badges-and-visuals.md](references/badges-and-visuals.md).

## Writing Style

- **Active voice, imperative mood**: "Install the package" not "The package can be installed"
- **Second person, present tense**: "You can configure..." with contractions for conversational tone
- **Short paragraphs**: Max 3-5 lines, one concept per paragraph
- **Emojis**: Use liberally on section headers (🚀 Quick Start), feature bullets (⚡ Fast), status indicators (✅ Done), and CTAs (⭐ Star us!). 2-4 per section, never in code blocks.

## README by Project Type

For detailed templates and examples by project type (AI/ML, CLI, Libraries, Web Apps), see [references/project-types.md](references/project-types.md).

For visual elements, social proof, and community links, see [references/badges-and-visuals.md](references/badges-and-visuals.md).

## Workflow

### Create Workflow

1. **Detect project type**: `uv run shared/detect_project.py --path "$(pwd)"`
2. **Extract metadata** — name, description, version, author, license. Use `pyproject.toml` `description` as tagline if available (add emojis, preserve core message). If no description, write crafted tagline back.
3. **Check archive status** — if `.archived.md` exists, read contents for archive notice (placed at README top)
4. **Check/generate logo** — look for `logo.png`, generate with project-logo-author if missing
5. **Calculate display width** — half actual pixel width for retina
6. **Generate README.md** — following Hook → Prove → Enable → Extend structure

### Modify Workflow

1. Read existing README, identify sections, detect custom content
2. Check `.archived.md` status — add/update/remove archive notice accordingly
3. Confirm uncertain deletions via AskUserQuestion
4. Apply requested changes (follow pyproject.toml tagline sync rules)
5. Validate result — no broken links or formatting

### Validate Workflow

Run Essential → Professional → Elite → Virality checklists plus project-type specifics. Calculate weighted score (Essential 40%, Professional 25%, Elite 15%, Virality 20%), generate report with actionable recommendations. See [references/validation-guide.md](references/validation-guide.md).

**Critical: Check section ordering against Hook → Prove → Enable → Extend.** Verify that value proposition / "why" sections appear before feature lists, quick start appears before deep reference docs, and extend content (contributing, community) comes last. Misordered sections undermine conversion regardless of content quality.

### Optimize Workflow

1. Run validation to identify issues
2. Apply quick wins (safe auto-fixes)
3. Present suggestions requiring approval (follow pyproject.toml tagline sync rules)
4. Re-validate and show improvement
