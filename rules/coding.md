# Coding standards

## Code style

- Comments in English only.
- Comment only to explain *why*, never *what* or *how*; code must be clear enough to express what it does through naming and structure alone.
- Do not write narrating comments (e.g. `// increment counter`, `// return result`, `// handle error`).
- Prefer renaming variables or extracting well-named functions over adding explanatory comments.
- Comments are appropriate for: non-obvious trade-offs, workarounds for external constraints, intent that cannot be expressed in code (regulatory requirements, algorithm selection rationale), and links to relevant tickets or specs.
- Prefer functional programming over object-oriented programming.
- Use classes only when the domain naturally requires rich objects, stateful behavior, or integration boundaries.
- Write pure functions: only modify return values; never mutate input parameters or global state.
- Make minimal, focused changes.
- Follow DRY, KISS, and YAGNI principles.
- Use strict typing everywhere: function returns, variables, collections.
- Check whether logic already exists before writing new code.
- Avoid untyped variables and loose generic typing.
- Avoid default parameter values: make callers pass explicit arguments (where the language and project conventions allow).
- Define proper types for complex data structures.
- Fail fast rather than masking problems with fallback behavior.

## Error handling

- Raise or return errors explicitly; never silently ignore failures.
- Use specific error types that indicate what went wrong.
- Avoid catch-all handlers that hide the root cause.
- Error messages must be clear and actionable.
- Do not substitute fallback behavior that hides defects: surface the failure and fix the primary path.
- When something fails, show what went wrong and why.
- Fix root causes, not symptoms.

## Language and modeling

- Prefer structured data models over loose dictionaries (for example Pydantic models or TypeScript interfaces).
- Avoid catch-all dynamic types such as `Any`, `unknown`, or `List[Dict[str, Any]]` unless the project already standardizes on them.
- Use modern package management (`pyproject.toml`, `package.json`, or the project’s equivalent).
- Throw or raise specific exceptions with descriptive messages.
- Use language features such as discriminated unions and enums where they clarify intent.
- Use classes for external system clients and boundaries; keep business logic in pure functions where practical.

## Libraries and dependencies

- Install into virtual environments or project-local toolchains, not global system Python/Node unless the project requires it.
- Add dependencies through project configuration files, not ad hoc one-off installs that bypass the lockfile or manifest.
- Explore and read source when understanding behavior instead of guessing.
- When adding a dependency, update the project’s dependency configuration in the same change.
