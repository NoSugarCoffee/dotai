# GitHub adapter

Use the installed `gh` CLI and its existing authentication. The helper needs REST
access for PR metadata, files and comments, plus GraphQL access for review-thread
resolution and outdated state. For publication, the login must be able to create
and edit review comments and ordinary PR comments. Do not fetch or print tokens.

```bash
python3 "$ROOT/scripts/review.py" snapshot --url "https://github.com/OWNER/REPO/pull/NUMBER" --output "$OUT/snapshot.json"
```

The URL selects the host, repository and PR explicitly. GitHub Enterprise URLs
with the same `/OWNER/REPO/pull/NUMBER` shape use `gh --hostname HOST`; they require
a login for that host. The returned canonical PR identity must match the request.
Fork PRs are addressed through the base repository's PR endpoint.

The normalized snapshot uses `diff_refs.base_sha` for the merge base,
`start_sha` for the current base-branch tip, and `head_sha` for the PR head.
The merge base comes from GitHub's comparison of those exact commit SHAs. Capture
checks revisions again after collection; publication rechecks all three before
each write. Both a new PR commit and movement of the base branch invalidate the
captured publication scope.

Files, inline review comments, ordinary comments, review bodies and thread states
are paginated. REST comments supply all replies; GraphQL supplies resolved and
outdated flags. If those collections disagree or thread state cannot be read, the
adapter stops rather than guessing whether an existing discussion may be updated.

Missing patches, patch addition/deletion count mismatches, and a file count that
differs from PR metadata become `coverage_gaps`. GitHub limits the files endpoint
to 3000 files. Preserve these gaps in `review.json` unless you obtain a new complete
snapshot; do not turn a partially captured PR into an approval.

Compute the SHA-256 of the exact snapshot bytes and put it in `review.json`.
Read full source at the pinned revisions through a verified local repository's
`git show SHA:path` or an authenticated GitHub file tool. For a fork, verify that
the requested head commit is available before using any checkout contents.

Continue with the [shared publication process](publishing.md). Inline comments
use the captured head as `commit_id`, the current filename (also for renames),
and `LEFT` for deleted lines or `RIGHT` for added/context lines. An old-side
context citation is translated to its new-side coordinate. The summary is an
ordinary PR comment. Neither operation submits an approving or requesting-changes
review event.

The existing finding schema is unchanged. `existing_discussion_id` is a snapshot
discussion ID: the root review comment's numeric ID as a string, or `review:ID`
for an existing top-level review. This allows duplicate findings to reference
existing feedback, including resolved threads. Ledgers store numeric comment and
author IDs; they remain specific to a provider, host, repository and PR number.

The helper sends JSON bodies through stdin to `gh api --input -`; source text and
comment bodies are never shell commands. A failed or timed-out write is not
automatically retried: inspect the server and receipts before attempting recovery.

API references: [review comments](https://docs.github.com/en/rest/pulls/comments#create-a-review-comment-for-a-pull-request),
[PR files](https://docs.github.com/en/rest/pulls/pulls#list-pull-requests-files),
[review threads](https://docs.github.com/en/graphql/reference/pulls#pullrequestreviewthread),
and [`gh api`](https://cli.github.com/manual/gh_api).
