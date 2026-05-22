---
name: project-logo-author
description: Generates professional logos with programmatic transparency conversion. Works with pixel art, vector designs, and complex multi-colored styles. Use when asked to "generate a logo", "create logo", or "make a project logo".
license: MIT
compatibility: requires repologogen CLI (pip install repologogen)
argument-hint: "[style-preference]"
disable-model-invocation: false
user-invocable: true
metadata:
  version: "6.0.0"
---

# Logo Generator

Generate professional logos with transparent backgrounds using the `repologogen` CLI.

## Pre-flight Check (MANDATORY)

Run `which repologogen` to verify the CLI is installed.

**If not found, STOP and inform the user:**
- Install with: `pip install repologogen` or `uv tool install repologogen`
- An `OPENROUTER_API_KEY` environment variable (or `~/.repologogen/config.yaml`) is required
- Link: https://github.com/tsilva/repologogen

**Do NOT proceed if repologogen is not installed.**

## Execution

Run from the project root:

```bash
repologogen [path] [flags]
```

### Flag Mapping

Map user preferences to CLI flags:

| User Request | Flag | Example |
|-------------|------|---------|
| Custom style | `-s` | `-s "pixel art"` |
| Output path | `-o` | `-o assets/logo.png` |
| Project name override | `-n` | `-n "My Project"` |
| Custom model | `-m` | `-m "openai/dall-e-3"` |
| Config file | `-c` | `-c custom-config.yaml` |
| Skip trimming | `--no-trim` | |
| Skip compression | `--no-compress` | |
| Preview only | `--dry-run` | |
| Template variables | `--var` | `--var KEY=VALUE` (repeatable) |
| Verbose output | `-v` | |

### Examples

```bash
# Default — auto-detects project, generates logo.png
repologogen

# Custom style
repologogen -s "16-bit pixel art"

# Custom output path with verbose logging
repologogen -o assets/logo.png -v

# Dry run to preview prompt
repologogen --dry-run

# Specific project directory
repologogen /path/to/project -s "minimalist vector"
```

## Configuration

repologogen loads config in priority order:
1. **Project**: `.config.yaml` in project root
2. **User**: `~/.repologogen/config.yaml`
3. **Built-in defaults**

See repologogen docs for all config options (`style`, `icon_colors`, `key_color`, `trim`, `compress`, etc.).

## Post-Generation

After `repologogen` completes, read the generated image with the Read tool to visually verify the result. If unsatisfactory, re-run with adjusted flags (e.g., different `-s` style).
