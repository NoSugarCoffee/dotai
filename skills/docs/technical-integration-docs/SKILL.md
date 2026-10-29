---
name: technical-integration-docs
description: Write, restructure, or review developer-facing integration guides, quickstarts, and API references. Use when readers need to choose an interface, make a first working call, automate a workflow, or look up an API contract.
---

# Technical integration documentation

Help a reader select a suitable interface, complete a concrete task, and find precise details when needed. Default to concise, example-led documentation: lead with the useful operation, put its request and response together, and state each fact once. Adapt to the user's chosen structure and level of detail.

For API usage documents, read [the API usage pattern](references/api-usage-pattern.md). It captures the preferred writing style; use it without requiring the user to choose a skill or template each time.

## Understand the task

1. Identify the intended reader, their goal, the available interfaces, and the expected result. Infer these from the request and existing material; ask only when a missing choice would materially change the document.
2. Inspect the existing document and relevant links before proposing a reorganization. Keep useful anchors, examples, assets, and child pages discoverable. Respect the requested scope and the owner's chosen source of truth.
3. Check technical claims against the implementation, tests, schemas, and current deployment or release evidence as available. Trace options through the execution path that determines their effect, including workers for asynchronous APIs. A boolean's name or default does not establish what either value does. State the actual effect and any design limitation directly; distinguish unknown behavior from verified behavior.
4. Establish availability from current release evidence. Keep MR history, rollout logs, and verification reports outside API usage prose; include an availability note only when it affects whether the reader can call the interface.

## Choose the shape

Separate the reader's decisions, task instructions, and facts to look up. Use links and clear headings to connect them; split pages when audiences or detail make a page hard to navigate. Keep a small document together when that serves the reader better.

- **Entry point:** Start with the reader's goal and the recommended route. When several interfaces are genuinely relevant, compare their outcomes, intended users, credentials, and links. Make the difference between similarly named interfaces clear.
- **Quickstart or how-to:** State the outcome and prerequisites, then give a short sequence leading to a visible result. Introduce authentication and setup where needed and link to deeper procedures. Show what success looks like and where to go when a step fails.
- **API usage or reference:** Keep each operation's method, path, parameters, request, and response together. Use a separate reference only when it adds needed depth; a small API can have one complete page. Label partial response examples as excerpts.
- **Explanation:** Put concepts, architecture, and rationale where they help a reader make a decision. Move protocol internals and historical migration details out of the first-success path unless they are required for the task.

Do not create a rigid page hierarchy or a choice table merely to satisfy a template. Split when audiences or tasks justify independent guides. A summary page should make the relevant guides discoverable, with link labels matching their actual titles. Prefer a single maintained home for each detailed contract. Preserve existing useful material when moving or condensing it.

## Write integration and API examples

- Use the real interface and verified environment. State required credentials, permissions, scopes, prerequisites, and availability per operation; do not assume that all endpoints share an authentication rule.
- Make examples safe and reproducible: use clearly named placeholders or environment variables, encode query parameters where needed, declare required tools, and avoid real secrets or shared session identifiers. Include a representative response and explain the fields needed for the next step.
- For asynchronous jobs, distinguish request acceptance, successful status retrieval, and successful job completion. Show submission and status retrieval as API operations; add a polling script only when requested. Document identifier reuse, retention, retries, concurrency, or cancellation only to the extent the actual contract supports them.
- Consolidate shared authentication and errors. When endpoints return the same HTTP status code, prefer one row per code and state endpoint-specific differences within that row or one short exception note. Avoid a second FAQ or reference that restates the same contract.
- Describe caller-visible behavior in plain language. Include protocol or implementation details only when they change how the reader sends a request or interprets a response. State conditions explicitly rather than hiding known behavior behind vague qualifiers.
- Use descriptive headings, numbered steps for procedures, and tables for comparisons or field lookups. Match the document's language and terminology. Prefer plain instructions and short examples over a catalogue of every implementation detail.

## Review and verify

For a review, cite specific passages or anchors, explain the reader impact, and prioritize actionable issues. Provide a proposed outline or a small rewritten example when it makes the recommendation concrete. Make edits when the user requests them; preserve unrelated content and resources.

Before finishing, check the structure, links, examples, and release labels against the evidence. Validate commands or snippets safely when practical, using an authorized test environment for operations that change state. Distinguish syntax checks, HTTP checks, and completed end-to-end tests; an accepted or running job is not a successful generation test.

After editing a remote document, read back the affected section and confirm formatting, examples, and unrelated content survived. Check that link destinations are readable, labels match destination titles, and any section anchors still exist. Repair links affected by moved or deleted content within the requested scope; do not invent fragment identifiers. Report access limitations separately from broken links.

For deeper guidance, see [Diátaxis](https://diataxis.fr/) on reader needs and [Google's procedure guidance](https://developers.google.com/style/procedures) on writing actionable steps.
