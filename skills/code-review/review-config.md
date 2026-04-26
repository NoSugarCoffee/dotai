# Review Configuration (Optional Overrides)

This file is **optional**. The code-review skill auto-detects your project's language,
framework, test framework, and linting conventions from project files. Only fill in
sections below if you need to **override** the auto-detected behavior.

## Language & Framework

```yaml
language: # e.g., TypeScript, Python, Go, Rust
framework: # e.g., Next.js, FastAPI, Spring Boot
test_framework: # e.g., Jest, pytest, JUnit
```

## Severity Threshold

Only report findings at or above this severity level.
Options: `critical`, `high`, `medium`, `low`

```yaml
minimum_severity: medium
```

## Team Conventions

Patterns your team uses intentionally — don't flag these:

```yaml
allowed_patterns:
  # - "We use bare booleans for React component props like visible, disabled"
  # - "We use any-casts in our legacy API layer (tech debt, tracked in JIRA-1234)"
  # - "Unused parameters in Express middleware are required by the framework"
```

## Patterns to Enforce

Team-specific rules to always check:

```yaml
enforced_patterns:
  # - "All database queries must use parameterized statements"
  # - "All API endpoints must have input validation"
  # - "No synchronous file I/O in request handlers"
  # - "All public functions must have JSDoc/docstrings"
```

## Known Tech Debt / Exceptions

Files or patterns to skip (they're known issues tracked elsewhere):

```yaml
exceptions:
  # - path: "src/legacy/**"
  #   reason: "Legacy module, scheduled for rewrite in Q3"
  # - pattern: "TODO(team):"
  #   reason: "Tracked TODOs, not review findings"
```

## Comparison Branch

Default branch to diff against:

```yaml
default_branch: main
```
