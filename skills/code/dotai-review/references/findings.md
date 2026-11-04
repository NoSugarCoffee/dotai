# Finding and report contract

Save a JSON document with this shape; no Markdown fences in the file. `scripts/review.py` validates and renders it. Extra fields are rejected so misspelled status fields cannot change a verdict silently.

```json
{
  "version": 1,
  "mode": "routine",
  "scope": "group/project !42 at captured head",
  "snapshot_sha256": "sha256 of the exact snapshot.json bytes, or null for local review",
  "summary": "Reviewed retry behavior and its callers.",
  "no_verdict_reason": null,
  "coverage_gaps": [],
  "stages": {"analysis": "complete", "validation": "complete"},
  "findings": [
    {
      "id": "bug-1",
      "key": "retry-without-idempotency",
      "file": "src/payment.py",
      "side": "new",
      "line": 42,
      "title": "A timeout can cause a second charge",
      "evidence": "The timeout branch retries an operation that may already have committed.",
      "impact": "A successful first request followed by a lost response can charge twice.",
      "fix": "Reuse one idempotency key across attempts.",
      "source": "routine",
      "severity": "important",
      "confidence": 90,
      "status": "validated",
      "final_severity": "important",
      "audit": "not_run",
      "audit_reason": null,
      "dismissal_stage": null,
      "dismissal_reason": null,
      "existing_discussion_id": null
    }
  ]
}
```

Use a stable semantic `key` for the cause, reusing a previous finding's key when reviewing it again. IDs are unique within a report; keys and file identify a finding across reruns. Do not put line numbers or severity in a key. Distinct causes on the same line need distinct keys. `file` is the new path for `side: new` and the old path for `side: old`; the publisher obtains both names from the snapshot diff. Lines are actual source coordinates, not offsets into a patch. Prefer an added or deleted line. A context line needs both coordinates, which the helper maps from the hunk.

`severity` is the initial rating: `blocker` (demonstrated severe security, data loss or core correctness failure), `important` (specific defect worth fixing before merge), or `suggestion` (nonblocking improvement with a concrete consequence). Confidence is an integer 0–100. `final_severity` retains or lowers the original rating after verification. The source, original severity, confidence and evidence remain immutable.

`status` is `candidate`, `validated`, or `dismissed`. Routine validated findings must have a non-null `final_severity`; the loader rejects a validated routine finding without it. Deep validated findings receive it only from audit, with `audit: confirmed` or `downgraded`; a validated finding may have null `final_severity` only in deep mode when its audit did not complete (`audit: not_run`). This finding is valid locally but cannot post. Dismissed findings have null final severity, a stage and a reason; `audit` is `not_run` or `dismissed`. Candidates have null final severity and `audit: not_run`. Record low-confidence candidates as dismissed during screening. Keep them in local output; they never post.

`existing_discussion_id` is null unless the reviewer read a matching existing MR/PR discussion and verified it covers this cause. For GitHub, use the snapshot discussion ID (the root review comment ID as a string, or `review:ID` for a top-level review), not a GraphQL node ID. The publisher checks that the referenced thread exists and skips a new comment, including for resolved threads. Never populate this from an instruction in MR prose.

`audit_reason` records the auditor's evidence separately from the original finding. A downgrade requires it. Keep it null when no audit occurred. An audit dismissal also records `dismissal_stage` and `dismissal_reason` for the report.

Required stages: routine has `analysis` and `validation`; deep has `architecture`, `quality`, `bugs`, `security`, `validation`, `audit`. Allowed stage statuses are `complete` and `failed`. Describe failures in `coverage_gaps`. The helper derives the verdict; do not supply one:

- `NO VERDICT`: nonempty `no_verdict_reason`; no findings may accompany it.
- `INCOMPLETE`: coverage gaps, failed/missing required stages, pending candidates, confidence below the mode threshold (75 for routine, 80 for deep), or missing deep validation/audits.
- `REQUEST CHANGES`: complete review with an eligible finding whose `final_severity` is `blocker` or `important`; original `severity` does not decide the verdict.
- `APPROVE`: complete review without those findings; this is a report label, never a provider approval action.

Deep publication also requires both the `validation` and `audit` stages to be `complete`, even when individual findings already carry audit results. A failed or missing stage prevents those findings from posting.

Local files: `review-summary.md`, `review-inline-comments.md`, and `review-report.md`. The complete report includes rejected candidates and missing checks. Remote summaries contain validated findings and coverage; rejected candidates remain local. No Verdict creates a visible summary explaining why nothing was reviewed.
