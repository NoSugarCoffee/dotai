# Concise API usage pattern

Use this style for developer-facing HTTP API usage. It is a starting point, not a mandatory page hierarchy. Adapt to the user's explicit choices.

## Shape

Start with the outcome and service address. Document shared credentials and example variables once, naming any operation that has a different authentication requirement.

For each operation, keep these together:

1. A descriptive operation heading and exact `METHOD /path`.
2. Inputs: name, location, type, required/default, constraints, and caller-visible effect. Use a small table when it is easier to scan than prose.
3. One complete curl request, with consistent variables and URL encoding.
4. The expected HTTP response and a matching JSON example. Label excerpts; explain only the fields needed to interpret the result or make the next call.

For a small asynchronous API, submission and status retrieval fit on the same page. State terminal states and how to retrieve the result or failure. Add advanced field definitions only when readers need them.

Keep common errors in one place. Prefer a two-column status/meaning table, with each HTTP status code appearing once. Put operation-specific distinctions in the meaning, or use one short exception note. Use separate tables only when the contracts are substantially different.

## Precision

- Describe behavior established by implementation and evidence. For a boolean, identify what `true` and `false` actually change. If the implementation does not provide the expected distinction, state that limitation; do not invent useful semantics from the parameter name.
- Distinguish optional, empty, and nullable inputs. State defaults only where they apply.
- Keep examples internally consistent: the same base URL, repository variable, identifier, authentication header, and response shape throughout.
- Use example identifiers rather than live shared identifiers. Show where a subsequent request obtains its identifier.
- Document the actual error envelope and applicable status codes. Avoid importing generic errors, rate limits, pagination, SDKs, or retries that the interface does not support.

## Editing and completion

Preserve the requested scope. When applying a chosen draft to part of an existing guide, retain other operations and reuse its shared setup. A new section should not introduce incompatible variable names or duplicate authentication instructions.

An API usage update is ready when its input descriptions agree with the implementation, its examples are syntactically valid and consistent with observed responses, each shared fact has one home, and remote read-back confirms the content and navigation survived. A test that only returns `202` supports acceptance; a claim of end-to-end success requires a terminal successful result.

## Sources

The preferred concise, reader-first, example-led style draws from [Anthropic's documentation skill](https://github.com/anthropics/knowledge-work-plugins/blob/main/engineering/skills/documentation/SKILL.md). Endpoint and parameter coverage is informed by [technical-documentation's API reference](https://github.com/magnus919/agent-skills/blob/main/technical-documentation/references/api-documentation-cli-help.md). Treat those as guidance, and verify API-specific claims against the actual contract.
