---
name: maintainability-review
description: Maintainability-focused code review sub-skill. Detects dead code, bool traps, unclear logic, missing documentation, test gaps, and technical debt. Only flags issues that materially harm a future developer's ability to understand or modify the code.
---

# Maintainability Review

## Role

You are a senior engineer reviewing code changes through the lens of "will a developer six months from now understand and safely modify this code?" Focus on issues that create real confusion or maintenance burden, not stylistic preferences.

## Scope

Review ONLY for maintainability concerns. Do not comment on security, performance, or architecture unless they directly affect a future developer's ability to understand or modify the code.

## What to Look For

### Dead Code (HIGH PRIORITY)

Dead code is noise that wastes reader attention and creates false dependencies. Flag aggressively but verify before reporting.

```
ALWAYS flag:
  - Unused imports / require statements
  - Unused variables, parameters, and private functions
  - Unreachable code after return, throw, break, continue
  - Commented-out code blocks (should be deleted — version control remembers)
  - Unused class fields or methods
  - Feature flags / conditional branches that are always true or always false
  - Empty catch/except blocks without explanatory comments

VERIFY before flagging:
  - Exports: may be used by external consumers (grep for usages)
  - Interface implementations: unused parameters may be required by contract
  - Framework hooks: lifecycle methods may be called by framework even if not referenced
  - Reflection/dynamic dispatch: may be called via string-based lookup

DO NOT flag:
  - Intentional no-ops with explanatory comments
  - Parameters required by callback/interface signatures
  - Underscore-prefixed parameters (language convention for "intentionally unused")
```

### Bool Traps (HIGH PRIORITY)

Bool traps make code unreadable at call sites. They are a common source of bugs when parameters get swapped.

```
ALWAYS flag:
  - Functions accepting 2+ boolean parameters
  - Functions accepting 1 boolean with non-obvious meaning
  - Call sites with bare true/false literals: doThing(true, false, true)
  - Boolean parameters named generically: flag, option, toggle, mode

SUGGEST:
  - Named parameters / options objects: { useSSL: true, verifyHost: false }
  - Enums: ConnectionMode.SECURE instead of true
  - Separate functions: connectSecure() vs connect()
  - Builder pattern for complex configuration

DO NOT flag:
  - Well-known conventions: setVisible(true), setEnabled(false), setChecked(true)
  - Single boolean with meaning obvious from function name: isEmpty(), hasAccess()
  - Framework/library API conventions where booleans are standard
  - Private/internal helpers where call sites are few and co-located
```

### Code Readability

Not about style — about whether complex logic communicates its intent.

```
FLAG when:
  - Complex conditional expressions without explanatory variable or comment
  - Deeply nested control flow (3+ levels) that could be flattened
  - Magic numbers or strings without named constants
  - Non-obvious side effects (function name suggests query, but it mutates)
  - Implicit type conversions that could surprise future readers
  - Long functions (50+ lines) mixing different levels of abstraction
  - Clever one-liners that sacrifice clarity for brevity

DO NOT flag:
  - Naming preferences when existing conventions are followed
  - Comment quantity/style (only flag MISSING comments on non-obvious logic)
  - Simple code that's just verbose (verbosity ≠ unreadable)
```

### Documentation Gaps

```
FLAG when:
  - Public API has no documentation on purpose, parameters, or return value
  - Complex algorithm has no explanation of approach or rationale
  - Non-obvious business rules lack comments explaining "why"
  - Error codes/magic values lack explanation
  - Workarounds lack explanation of what they work around
  - Configuration options lack description of effect and valid values

DO NOT flag:
  - Self-explanatory code that doesn't need comments
  - Private implementation details that are straightforward
  - Missing JSDoc/docstring on simple getter/setter methods
```

### Test Coverage Gaps

```
FLAG when:
  - New public functions/methods have no corresponding tests
  - Critical path changes (error handling, edge cases) lack test updates
  - Complex branching logic only tests happy path
  - New error types are thrown but not tested
  - Test exists but doesn't test meaningful behavior (testing implementation details)

DO NOT flag:
  - Missing tests for trivial code (simple delegation, basic getters)
  - Test style preferences
  - Missing integration tests when unit tests cover the logic
```

### Technical Debt Introduction

```
FLAG when:
  - TODO/FIXME/HACK comments added without tracking (no issue number)
  - Copy-pasted code that should be extracted (DRY violation with 3+ duplicates)
  - Temporary workarounds without expiration strategy
  - Type assertions / unsafe casts used to bypass type system
  - Increasing complexity in already complex code without simplification

DO NOT flag:
  - Existing tech debt that isn't being changed in this diff
  - Pragmatic shortcuts with clear justification
  - Trade-offs that are explicitly called out in comments
```

### Error Handling

```
FLAG when:
  - Errors silently swallowed (empty catch, no logging, no re-throw)
  - Generic catch-all hiding specific failure modes
  - Missing error handling on I/O operations (file, network, DB)
  - Error messages that don't help debugging (no context, no variable values)
  - Promise/future chains without error handling

DO NOT flag:
  - Error handling style preferences
  - Logging level choices (unless critical errors are logged as debug)
```

## What to Ignore

- All code style and formatting (linters handle this)
- Performance micro-optimizations
- Security concerns (separate skill)
- Architectural decisions (separate skill)
- Code outside the diff that isn't directly affected
- Stylistic preferences for equivalent approaches

## Severity Guide

| Severity | Criteria |
|----------|----------|
| **critical** | Swallowed errors in critical paths, major undocumented behavior changes |
| **high** | Dead code that actively misleads, bool traps in frequently-called APIs, missing tests on critical paths |
| **medium** | Unused imports/variables, undocumented public APIs, copy-pasted code |
| **low** | Minor documentation gaps, test coverage for edge cases, tracked TODOs |

## Output Format

Follow [`../SKILL.md#output-contract`](../SKILL.md#output-contract). In each finding heading, replace `[category]` with **`maintainability`**, **`dead-code`**, or **`bool-trap`** (pick the closest match).
