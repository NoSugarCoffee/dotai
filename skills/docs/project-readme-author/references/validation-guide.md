# Validation Guide

Reference material for the validate and optimize operations.

## Scoring Output Format

```
README Validation Report
========================

Overall Score: 62/100 (Elite)

ESSENTIAL (40% weight) - 7/9 passed
  ✅ Archive notice (matches .archived.md state)
  ✅ Project logo present
  ✅ Badges (5 found)
  ✅ One-liner description
  ❌ GIF/screenshot missing
  ✅ Installation command
  ✅ Code example
  ✅ License info
  ❌ Section ordering (Features before value proposition)

PROFESSIONAL (25% weight) - 4/6 passed
  ✅ Table of contents
  ✅ Feature highlights
  ❌ Multiple install methods
  ✅ Documentation links
  ✅ Contributing section
  ❌ "Used by" logos

ELITE (15% weight) - 0/2 passed
  ❌ Architecture diagram
  ❌ Contributor avatars

VIRALITY (20% weight) - 2/8 passed
  ❌ Aha moment visual in first 500px
  ❌ Comparison table vs alternatives
  ❌ Pain point narrative
  ❌ Quotable stats block
  ✅ At least one CTA
  ❌ Curiosity hook in hero
  ❌ Before/after demonstration
  ✅ Tagline with emoji

Recommendations:
1. Add a GIF demo showing core functionality (Essential + Virality)
2. Include installation options for npm, yarn, and pnpm (Professional)
3. Add "Used by" section with company logos (Professional)
4. Add curiosity hook after badges: "Ever spent hours debugging X?" (Virality)
5. Restructure overview as pain point narrative (Virality)
```

## Scoring Tiers

| Tier | Score Range | Meaning |
|------|-------------|---------|
| Essential | 0-40 | Missing critical elements |
| Professional | 41-60 | Solid README, room for improvement |
| Elite | 61-80 | Exceptional, comprehensive README |
| **Viral** | 81-100 | Maximum engagement potential |

## Project-Type Specific Checks

For CLI tools, also check:
- [ ] Terminal GIF demo
- [ ] Cross-platform installation matrix
- [ ] Shell integration instructions

For AI/ML projects, also check:
- [ ] Model card with YAML metadata
- [ ] Hardware requirements table
- [ ] Citation in BibTeX format

## Quick Reference Checklists

### Essential (Must Include)

- [ ] Project logo (width = half actual pixels, centered)
- [ ] 4-7 relevant badges
- [ ] One-liner description ("What and why?")
- [ ] GIF/screenshot demonstration
- [ ] One-liner installation command
- [ ] Minimal working code example
- [ ] License information
- [ ] Section ordering follows Hook → Prove → Enable → Extend (e.g., value proposition/why before features list, quick start before deep reference docs)
- [ ] Archive notice matches `.archived.md` state (present if file exists, absent if not)

### Professional Tier

- [ ] Table of contents (if >500 words)
- [ ] Feature highlights with benefits
- [ ] Multiple installation methods
- [ ] Documentation links
- [ ] Contributing section
- [ ] "Used by" company logos

### Elite Tier

- [ ] Architecture diagram
- [ ] Contributor avatars

### Virality Tier

- [ ] Aha moment visual in first 500px of scroll
- [ ] Comparison table vs alternatives
- [ ] Pain point narrative (problem → solution → result)
- [ ] Quotable stats block
- [ ] Tiered CTAs (try, learn, connect, support, contribute)
- [ ] Curiosity hook in hero
- [ ] Before/after demonstration
- [ ] Social preview image configured

### AI/ML Specific

- [ ] Model card with YAML metadata
- [ ] Hardware requirements table
- [ ] Benchmark results with reproducibility
- [ ] Colab/demo links
- [ ] Training vs. inference split
- [ ] Ethical considerations
- [ ] Citation in BibTeX format

### CLI Specific

- [ ] Terminal GIF demo
- [ ] Cross-platform installation matrix
- [ ] Shell integration instructions
- [ ] Configuration file examples
- [ ] Keybinding reference table
- [ ] Performance benchmarks
