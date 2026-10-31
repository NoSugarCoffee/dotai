# GitLab adapter

Use the installed `idev-cli` and its existing authentication. Read the environment's `idev-code` and `idev-shared` skills before using it. Do not fetch or print tokens. No company hostname, gateway or credential is bundled here. `idev-cli` selects its configured GitLab instance; the snapshot command checks that the returned MR URL matches the requested host, project and IID.

The helper passes subprocess arguments directly, never through a shell. It paginates diffs, notes and discussions, captures all three `diff_refs`, and checks the revision again after collection. Python 3.9+ is sufficient and there are no third-party dependencies.

```bash
python3 "$ROOT/scripts/review.py" snapshot --url "$MR_URL" --output "$OUT/snapshot.json"
```

Compute the snapshot digest with `shasum -a 256 "$OUT/snapshot.json"` and copy it into `review.json`. The snapshot contains metadata, diff hunks and existing conversations. Read full files at the captured head via local `git show` or `idev-cli code file get --project PROJECT --path PATH --ref HEAD_SHA --json`. Verify local repository identity before using its source. Preserve skipped diff information in `coverage_gaps`; the idev diff model may omit server truncation flags, so do not claim full coverage from an empty hunk or metadata count mismatch.

After producing and inspecting the rendered report, prepare the publication plan:

```bash
python3 "$ROOT/scripts/review.py" publish --review "$OUT/review.json" --snapshot "$OUT/snapshot.json" --ledger "$OUT/publication.json"
```

This command only reads GitLab. It validates inline positions against the captured patch, compares all current diff refs with the snapshot, checks existing conversations and local publication receipts, and prints planned operations. Inspect the JSON plan and Markdown bodies. If the user requested posting, execute the same command with `--apply`. That flag is an execution switch, not a request for another approval.

Only validated findings above the selected confidence threshold post. Deep mode additionally requires a completed severity audit for each finding. An incomplete review can publish those verified findings, with an incomplete summary that exposes the gaps. If no valid diff position can be established for a finding, planning fails before writing; repair the citation or record the omitted coverage and rerender. Do not silently turn failed inline comments into ordinary notes.

The publisher keeps a local ledger of created IDs and returned author IDs, saving after each write. It updates only those recorded comments. Without a ledger, it refuses to overwrite pre-existing comments bearing this tool's marker; recover the original ledger or inspect and explicitly link existing discussions. It does not claim other authors' text merely because they copied a marker. A response lost after a write may require reconciling the returned IDs manually before retrying; never retry a timed-out creation blindly.

Resolved discussions and threads with another author's response are preserved; the plan reports them as skipped. Existing human discussions identified by the reviewer also suppress duplicate comments. Findings absent in a later review are not auto-resolved. The MR summary is a single ordinary note updated through its saved ID. Comments include the reviewed head revision.

Publishing checks the server revision before every write and stops if it changes. GitLab has no atomic transaction spanning these comments: a concurrent push or network failure can leave a partial publication. The ledger records completed writes for recovery. Serialize publishes for the same MR; the helper locks its ledger path, but two machines using different ledgers still require coordination.

No live MR is needed to test this package. Run the offline fixture tests from the README. Live posting requires an actual user-requested MR and authenticated CLI, and should not be substituted with a test comment on an arbitrary project.
