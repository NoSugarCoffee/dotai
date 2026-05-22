# Badges and Visual Elements

Reference material for badge implementation, visual elements, and social proof.

## Priority Badge for Virality

The star badge is the highest-impact social proof badge. Include if stars > 100:

```markdown
[![GitHub stars](https://img.shields.io/github/stars/user/repo?style=social)](https://github.com/user/repo)
```

## Badge Implementation

```markdown
[![Build](https://img.shields.io/github/actions/workflow/status/user/repo/ci.yml?branch=main)](link)
[![Coverage](https://img.shields.io/codecov/c/github/user/repo)](link)
[![PyPI](https://img.shields.io/pypi/v/package-name)](link)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](link)
[![Downloads](https://img.shields.io/pypi/dm/package-name)](link)
[![Discord](https://img.shields.io/discord/SERVER_ID)](link)
```

**Rules:**
- Use shields.io for all badges (consistent styling)
- Pick one style (flat, flat-square, for-the-badge) and use it consistently
- For CLI tools, include a Repology badge showing packaging status

## Impressive Metrics Badges

Only include metrics that are impressive. Thresholds:

| Metric | Include If | Badge |
|--------|------------|-------|
| Stars | > 100 | `![Stars](https://img.shields.io/github/stars/user/repo?style=social)` |
| Downloads | > 1000/week | `![Downloads](https://img.shields.io/pypi/dw/package)` |
| Contributors | > 10 | `![Contributors](https://img.shields.io/github/contributors/user/repo)` |
| Forks | > 50 | `![Forks](https://img.shields.io/github/forks/user/repo?style=social)` |
| Last commit | < 30 days | `![Last commit](https://img.shields.io/github/last-commit/user/repo)` |

**Rule:** If a metric isn't impressive, don't include it. A badge showing "2 stars" hurts more than it helps.

## Dark/Light Mode Support

For theme-aware logos, use the `<picture>` element:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="logo-light.png">
  <img src="logo-light.png" alt="Project Name" width="{DISPLAY_WIDTH}">
</picture>
```

## Visual Elements

### GIF Demos (Mandatory for CLI Tools)

Terminal recordings are mandatory for CLI tools. Use:
- **vhs** - scripted terminal GIFs (recommended)
- **terminalizer** - interactive recording
- **asciinema** - terminal session sharing

**GIF Requirements:**
- Under 10MB (GitHub limit)
- 10-15fps is sufficient
- Show the "aha moment" - core value in action
- Drag-drop into README editor to host on GitHub's CDN

### Screenshots

For UI-heavy projects:
- Include both light and dark mode versions
- Compress before adding (ImageOptim, XConvert)
- Use descriptive alt text

### Tables

Use tables for:
- Feature comparisons
- API parameters
- Benchmark results
- Installation matrices (cross-platform)

### Architecture Diagrams

For complex projects, use Mermaid (GitHub-native):

```markdown
```mermaid
graph LR
    A[Input] --> B[Process]
    B --> C[Output]
```
```

## Social Proof

### "Used By" Section

Place prominently after hero section with 6-12 company logos:

```markdown
## Used By

<p align="center">
  <img src="logos/company1.svg" alt="Company 1" height="40">
  &nbsp;&nbsp;&nbsp;
  <img src="logos/company2.svg" alt="Company 2" height="40">
</p>
```

### Star CTA

Engaging call-to-action patterns:
- `⭐ Star if this saved you hours of debugging!`
- `🌟 If this helped, a star would make our day!`

**Rules**: One CTA max. Humor optional but never cringe.

### Testimonial Formatting

Format endorsements for maximum impact:

```markdown
> "This tool is incredible. Saved us 10 hours/week."
> — [@notable_person](https://twitter.com/notable_person), CTO at Company

> "The best debugging tool I've used in years."
> — [@developer](https://github.com/developer), Maintainer of PopularProject
```

**Rules:**
- Include real link to person's profile
- Include role and company/project for authority
- Quote must be permission-granted or public (from tweet, blog post, etc.)
- Prioritize: industry leaders > popular project maintainers > power users

### Community Links

```markdown
[![Discord](https://img.shields.io/discord/SERVER_ID?label=Discord&logo=discord)](link)
[![Twitter](https://img.shields.io/twitter/follow/handle?style=social)](link)
```

### Supporting Files

These files signal project maturity:
- CONTRIBUTING.md
- CODE_OF_CONDUCT.md
- SECURITY.md
- LICENSE
