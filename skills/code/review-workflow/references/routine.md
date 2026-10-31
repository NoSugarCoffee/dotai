# Routine review

One reviewer examines the full captured change, then makes a separate pass challenging its own candidates. In a plugin session the caller delegates to `dotai-review:routine-reviewer`; in another runtime use a read-only worker or execute the process in the current agent. This mode does not promise independent verification.

1. Summarize intent, changed contracts, callers, trust boundaries, migrations, configuration, and relevant tests. Read enough surrounding code to understand how the changed path runs.
2. Analyze security and correctness first, then compatibility, performance, and maintenance problems with concrete consequences. Trace error paths and state transitions. Check dependency changes against actual lockfile and compatibility requirements; do not import another company's approval policy.
3. Create candidates using the finding contract. Use confidence 75 as the initial screening threshold. A lower-confidence concern may be recorded as dismissed locally, but does not become a GitLab comment.
4. For each surviving candidate, actively look for disconfirming evidence: a caller validates the value, a framework guarantees it, a bound makes the alleged cost trivial, an equivalent safeguard exists, or the behavior predates the change. Explain the execution path that still fails. Reject unsupported claims with a reason.
5. Assign final severity based on demonstrated impact. Keep `audit: not_run` because this path has no independent audit. Deduplicate candidates describing the same cause and effect. Read existing MR discussions when available; link matching threads instead of multiplying comments. Respect a human resolution; do not reopen or reply automatically.
6. Return the finding list and stages `analysis` and `validation`, each `complete` or `failed`, with any coverage gaps. No output is emitted remotely by this reviewer.

Do not reject a real bug simply because the change is deliberate. Check associated callers, registries, types, and migrations: an intentional new contract can still leave one of them inconsistent.
