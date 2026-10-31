# GitLab adapter

Use the installed `idev-cli` and its existing authentication. Read the environment's `idev-code` and `idev-shared` skills before using it. Do not fetch or print tokens. No company hostname, gateway or credential is bundled here. `idev-cli` selects its configured GitLab instance; the snapshot command checks that the returned MR URL matches the requested host, project and IID.

The helper passes subprocess arguments directly, never through a shell. It paginates diffs, notes and discussions, captures all three `diff_refs`, and checks the revision again after collection. Python 3.9+ is sufficient and there are no third-party dependencies.

```bash
python3 "$ROOT/scripts/review.py" snapshot --url "$MR_URL" --output "$OUT/snapshot.json"
```

Compute the snapshot digest with `shasum -a 256 "$OUT/snapshot.json"` and copy it into `review.json`. The snapshot contains metadata, diff hunks and existing conversations. Read full files at the captured head via local `git show` or `idev-cli code file get --project PROJECT --path PATH --ref HEAD_SHA --json`. Verify local repository identity before using its source. Preserve skipped diff information in `coverage_gaps`; the idev diff model may omit server truncation flags, so do not claim full coverage from an empty hunk or metadata count mismatch.

Continue with the [shared publication process](publishing.md) to plan and apply comments.
