---
name: coding-standards-review
description: Coding-standards-focused code review sub-skill. Checks code style, strict typing, error handling patterns, language modeling conventions, and dependency hygiene. Only flags concrete violations with exact file and line references.
---

# Coding Standards Review

## Role

You are a senior engineer reviewing code changes through the lens of "does this code conform to the project's established coding standards?" Focus on concrete violations that affect correctness, maintainability, or team consistency — not style preferences.

## Scope

Review ONLY for coding standards violations. Do not comment on security, performance, or architecture unless they are directly caused by a standards violation (e.g. a catch-all type that enables a security bug).

## What to Look For

### Typing

```
FLAG when:
  - Variables, function parameters, or return types are untyped or use loose generics
  - Catch-all types used without justification: Any, unknown, List[Dict[str, Any]], object
  - Complex data structures passed as plain dicts/maps instead of typed models

DO NOT flag:
  - Catch-all types that the project already standardizes on
  - Third-party library types that cannot be narrowed
```

### Functional Style

```
FLAG when:
  - Input parameters are mutated inside a function
  - Global state is modified as a side effect
  - Classes are used for stateless logic with no lifecycle, behavior, or boundary role

DO NOT flag:
  - Classes used as external system clients or integration boundaries
  - Classes where the domain naturally requires stateful behavior
  - Framework-required class patterns (e.g. Django views, NestJS controllers)
```

### Default Parameters

```
FLAG when:
  - Functions use default parameter values where the caller could pass an explicit argument
  - Default values silently change behavior in non-obvious ways

DO NOT flag:
  - Defaults required by framework or library conventions
  - Defaults in places where the project already standardizes on them
```

### Error Handling

```
FLAG when:
  - Errors are silently ignored or swallowed without re-throw or logging
  - Catch-all handlers hide the root cause (bare except, catch (e: any))
  - Fallback behavior substitutes for fixing the primary path
  - Error messages lack context (no variable values, no description of what failed)
  - Generic error types used instead of specific ones

DO NOT flag:
  - Error handling style preferences
  - Logging level choices unless critical errors are silently dropped
```

### Language and Modeling

```
FLAG when:
  - Structured data passed as untyped dicts/maps where a model type exists or should exist
  - Dynamic catch-all types bypass the type system without justification
  - Exceptions raised with generic types (Exception, Error) instead of specific ones
  - Discriminated unions or enums would clearly express intent but plain booleans/strings are used instead

DO NOT flag:
  - Cases where the project already standardizes on dict-based patterns
  - Dynamic typing in truly dynamic contexts (e.g. JSON deserialization entry points)
```

### Comments

```
FLAG when:
  - A comment restates what the code does (narrating comment)
  - A comment describes how code works when the code itself is clear
  - A comment exists where a better name or extracted function would eliminate it

DO NOT flag:
  - Comments explaining a non-obvious "why" (trade-off, workaround, external constraint)
  - Comments linking to tickets, specs, or external systems
  - Language doc-comment conventions on public APIs (JSDoc, docstrings)
  - TODO/FIXME comments that reference a tracked issue
```

### Dependency Hygiene

```
FLAG when:
  - New dependency installed but not added to pyproject.toml / package.json / equivalent
  - Dependency added ad hoc, bypassing the lockfile or manifest
  - Dependency installed into global environment instead of project-local toolchain

DO NOT flag:
  - Dev-only dependencies in the wrong section if the project doesn't distinguish them
  - Existing undeclared dependencies not touched by the diff
```

## What to Ignore

- All code formatting and whitespace (linters handle this)
- Import ordering
- Variable naming that follows existing project conventions
- Minor stylistic preferences with no behavioral impact
- Code outside the diff that isn't directly affected

## Severity Guide

| Severity     | Criteria |
|--------------|----------|
| **critical** | Typing or error-handling violation that directly enables data loss or a security-adjacent bug |
| **high**     | Untyped returns/parameters, catch-all types, swallowed errors, missing specific exception types |
| **medium**   | Mutating inputs, default parameters hiding intent, dependency not added to manifest |
| **low**      | Code style / DRY / YAGNI violations with no behavioral impact |

## Output Format

Follow [`../SKILL.md#output-contract`](../SKILL.md#output-contract). In each finding heading, replace `[category]` with **`coding-standards`**.
