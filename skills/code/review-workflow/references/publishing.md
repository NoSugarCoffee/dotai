# Shared publication process

Use the [GitLab](gitlab.md) or [GitHub](github.md) adapter to capture the target first. The snapshot and ledger formats are shared; existing GitLab receipts remain usable.

After producing and inspecting the rendered report, prepare the publication plan:

```bash
python3 "$ROOT/scripts/review.py" publish --review "$OUT/review.json" --snapshot "$OUT/snapshot.json" --ledger "$OUT/publication.json"
```

This command only reads the selected provider. It validates inline positions against the captured patch, compares all current diff refs with the snapshot, checks existing conversations and local publication receipts, and prints planned operations. Inspect the JSON plan and Markdown bodies. If the user requested posting, execute the same command with `--apply`. That flag is an execution switch, not a request for another approval.

Only validated findings above the selected confidence threshold post. Deep mode additionally requires a completed severity audit for each finding. An incomplete review can publish those verified findings, with an incomplete summary that exposes the gaps. If no valid diff position can be established for a finding, planning fails before writing; repair the citation or record the omitted coverage and rerender. Do not silently turn failed inline comments into ordinary notes.

The publisher keeps a local ledger of created IDs and returned author IDs, saving after each write. It updates only those recorded comments. Without a ledger, it refuses to overwrite pre-existing comments bearing this tool's marker; recover the original ledger or inspect and explicitly link existing discussions. It does not claim other authors' text merely because they copied a marker. A response lost after a write may require reconciling the returned IDs manually before retrying; never retry a timed-out creation blindly.

Resolved or outdated discussions and threads with another author's response are preserved; the plan reports them as skipped. Existing human discussions identified by the reviewer also suppress duplicate comments. Findings absent in a later review are not auto-resolved. The MR/PR summary is a single ordinary comment updated through its saved ID. Comments include the reviewed head revision.

Publishing checks the server revision before every write and stops if it changes. Neither adapter has an atomic transaction spanning these comments: a concurrent push or network failure can leave a partial publication. The ledger records completed writes for recovery. Serialize publishes for the same MR/PR; the helper locks its ledger path, but two machines using different ledgers still require coordination.

No live MR/PR is needed to test this package. Run the offline fixture tests from the README. Live posting requires an actual user-requested MR/PR and authenticated CLI, and should not be substituted with a test comment on an arbitrary project.
