#!/usr/bin/env python3
"""Render review records and publish revision-bound GitLab discussions via idev-cli."""
from __future__ import annotations

import argparse
import dataclasses
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Union, cast
from urllib.parse import urlparse

JSON = Union[None, bool, int, float, str, List["JSON"], Dict[str, "JSON"]]
Object = Dict[str, JSON]
SEVERITIES = ("blocker", "important", "suggestion")
REQUIRED = {
    "routine": {"analysis", "validation"},
    "deep": {"architecture", "quality", "bugs", "security", "validation", "audit"},
}
PREFIX = "<!-- dotai-review:"


class ReviewError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReviewError(message)


def obj(value: JSON) -> Object:
    require(isinstance(value, dict), "Expected a JSON object")
    return cast(Object, value)


def records(value: JSON) -> List[Object]:
    require(isinstance(value, list), "Expected a JSON array")
    return [obj(item) for item in cast(List[JSON], value)]


def string(value: JSON) -> str:
    require(isinstance(value, str), "Expected a string")
    return cast(str, value)


def read_json(path: Path) -> JSON:
    return cast(JSON, json.loads(path.read_text()))


def write_json(path: Path, value: JSON) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".review-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@dataclasses.dataclass(frozen=True)
class Finding:
    id: str
    key: str
    file: str
    side: str
    line: int
    title: str
    evidence: str
    impact: str
    fix: str
    source: str
    severity: str
    confidence: int
    status: str
    final_severity: Optional[str]
    audit: str
    audit_reason: Optional[str]
    dismissal_stage: Optional[str]
    dismissal_reason: Optional[str]
    existing_discussion_id: Optional[str]


def finding(value: Object) -> Finding:
    require(set(value) == {f.name for f in dataclasses.fields(Finding)}, "Invalid finding fields")
    text_fields = ("id", "key", "file", "side", "title", "evidence", "impact", "fix", "source", "severity", "status", "audit")
    for field in text_fields:
        require(isinstance(value[field], str) and bool(value[field]), "Empty/invalid finding " + field)
    for field in ("final_severity", "audit_reason", "dismissal_stage", "dismissal_reason", "existing_discussion_id"):
        require(value[field] is None or (isinstance(value[field], str) and bool(value[field])), "Invalid " + field)
    require(type(value["line"]) is int and cast(int, value["line"]) > 0, "Line must be positive")
    require(type(value["confidence"]) is int and 0 <= cast(int, value["confidence"]) <= 100, "Invalid confidence")
    f = Finding(**value)  # type: ignore[arg-type]
    require(bool(re.fullmatch(r"[a-z0-9][a-z0-9-]*", f.key)), "Finding key must be a semantic slug")
    require(f.side in ("old", "new") and f.severity in SEVERITIES, "Invalid side or severity")
    require(not Path(f.file).is_absolute() and ".." not in Path(f.file).parts, "Finding path must be repo-relative")
    require(f.status in ("candidate", "validated", "dismissed"), "Invalid finding status")
    require(f.audit in ("not_run", "confirmed", "downgraded", "dismissed"), "Invalid audit")
    if f.status == "validated":
        require(f.final_severity in SEVERITIES or (f.final_severity is None and f.audit == "not_run"), "Audited finding needs final severity")
        if f.final_severity is not None:
            require(SEVERITIES.index(f.final_severity) >= SEVERITIES.index(f.severity), "Audit cannot upgrade severity")
        require(f.audit != "dismissed" and f.dismissal_reason is None and f.dismissal_stage is None, "Contradictory validated finding")
        require(f.audit != "confirmed" or f.final_severity == f.severity, "Confirmed audit changed severity")
        require(f.audit != "downgraded" or f.final_severity != f.severity, "Downgrade must lower severity")
        require(f.audit != "downgraded" or bool(f.audit_reason), "Downgrade needs an audit reason")
    else:
        require(f.final_severity is None, "Unvalidated finding cannot have final severity")
        if f.status == "dismissed":
            require(bool(f.dismissal_reason) and bool(f.dismissal_stage), "Dismissal needs stage and reason")
            require(f.audit in ("not_run", "dismissed"), "Invalid dismissed audit")
        else:
            require(f.audit == "not_run" and f.dismissal_reason is None and f.dismissal_stage is None, "Invalid candidate")
    return f


@dataclasses.dataclass(frozen=True)
class Review:
    mode: str
    scope: str
    snapshot_sha256: Optional[str]
    summary: str
    no_verdict_reason: Optional[str]
    coverage_gaps: List[str]
    stages: Dict[str, str]
    findings: List[Finding]


def load_review(path: Path) -> Review:
    data = obj(read_json(path))
    require(set(data) == {f.name for f in dataclasses.fields(Review)} | {"version"}, "Invalid review fields")
    require(data["version"] == 1 and data["mode"] in REQUIRED, "Unsupported version or mode")
    for key in ("scope", "summary"):
        require(isinstance(data[key], str) and bool(data[key]), "Missing " + key)
    require(data["snapshot_sha256"] is None or bool(re.fullmatch(r"[a-f0-9]{64}", string(data["snapshot_sha256"]))), "Invalid snapshot digest")
    require(data["no_verdict_reason"] is None or bool(string(data["no_verdict_reason"])), "Invalid No Verdict reason")
    require(isinstance(data["coverage_gaps"], list) and all(isinstance(g, str) and g for g in cast(list, data["coverage_gaps"])), "Invalid coverage gaps")
    stages = obj(data["stages"])
    require(all(s in ("complete", "failed") for s in stages.values()), "Invalid stage status")
    findings = [finding(f) for f in records(data["findings"])]
    require(len({f.id for f in findings}) == len(findings), "Duplicate finding ID")
    require(len({(f.file, f.key) for f in findings}) == len(findings), "Duplicate finding key")
    require(not data["no_verdict_reason"] or not findings, "No Verdict cannot contain findings")
    return Review(string(data["mode"]), string(data["scope"]), cast(Optional[str], data["snapshot_sha256"]),
                  string(data["summary"]), cast(Optional[str], data["no_verdict_reason"]),
                  cast(List[str], data["coverage_gaps"]), cast(Dict[str, str], stages), findings)


def eligible(review: Review, f: Finding) -> bool:
    return (f.status == "validated" and f.final_severity in SEVERITIES and f.confidence >= (80 if review.mode == "deep" else 75)
            and (review.mode == "routine" or f.audit in ("confirmed", "downgraded")))


def gaps(review: Review) -> List[str]:
    missing = [s + " did not complete" for s in sorted(REQUIRED[review.mode]) if review.stages.get(s) != "complete"]
    failed_optional = [s + " failed" for s, v in review.stages.items() if v == "failed" and s not in REQUIRED[review.mode]]
    pending = [f.id + " is not verified" for f in review.findings if f.status != "dismissed" and not eligible(review, f)]
    return review.coverage_gaps + missing + failed_optional + pending


def verdict(review: Review) -> str:
    if review.no_verdict_reason:
        return "NO VERDICT"
    if gaps(review):
        return "INCOMPLETE"
    if any(eligible(review, f) and f.final_severity in ("blocker", "important") for f in review.findings):
        return "REQUEST CHANGES"
    return "APPROVE"


def finding_body(f: Finding) -> str:
    return (f"**{(f.final_severity or f.severity).upper()}: {f.title}**\n\n"
            f"`{f.file}:{f.line}` · {f.source}\n\n<details>\n<summary>Evidence and fix</summary>\n\n"
            f"{f.evidence}\n\n**Impact:** {f.impact}\n\n**Fix:** {f.fix}\n\n</details>"
            + (f"\n\n**Severity audit:** {f.audit_reason}" if f.audit_reason else ""))


def summary_body(review: Review) -> str:
    result = f"# Code review\n\n**Assessment:** {verdict(review)}\n\n**Scope:** {review.scope}\n\n{review.summary}\n"
    if review.no_verdict_reason:
        return result + "\n**Not reviewed:** " + review.no_verdict_reason + "\n"
    if gaps(review):
        result += "\n**Not covered or incomplete:**\n\n" + "\n".join("- " + g for g in gaps(review)) + "\n"
    kept = [f for f in review.findings if eligible(review, f)]
    result += "\n| Severity | Count |\n| --- | ---: |\n"
    result += "\n".join(f"| {s} | {sum(f.final_severity == s for f in kept)} |" for s in SEVERITIES) + "\n"
    if kept:
        result += "\n" + "\n".join(f"- **{f.final_severity}:** {f.title} — `{f.file}:{f.line}`" for f in kept) + "\n"
    return result


def render(review: Review, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    summary = summary_body(review)
    inline = "\n\n---\n\n".join(finding_body(f) for f in review.findings if eligible(review, f))
    report = summary + "\n## Findings\n\n" + (inline or "No verified findings.") + "\n"
    for status, heading in (("candidate", "Pending validation"), ("dismissed", "Reviewed and dismissed")):
        items = [f for f in review.findings if f.status == status]
        if items:
            report += f"\n## {heading}\n\n<details>\n<summary>{len(items)} findings</summary>\n\n"
            for f in items:
                report += finding_body(f) + f"\n\n**Original confidence:** {f.confidence}/100\n"
                if status == "dismissed":
                    report += f"\n**Dismissed at:** {f.dismissal_stage}\n\n**Reason:** {f.dismissal_reason}\n"
            report += "\n</details>\n"
    unverified = [f for f in review.findings if f.status == "validated" and not eligible(review, f)]
    if unverified:
        report += "\n## Awaiting verification or audit\n\n" + "\n\n".join(finding_body(f) for f in unverified) + "\n"
    for name, body in (("review-summary.md", summary), ("review-inline-comments.md", inline), ("review-report.md", report)):
        (output / name).write_text(body)


def mr_target(url: str) -> tuple[str, str, str]:
    parsed = urlparse(url)
    require(parsed.scheme == "https" and bool(parsed.hostname) and not parsed.username and not parsed.password
            and not parsed.query and not parsed.fragment, "Use an HTTPS MR URL without credentials, query or fragment")
    match = re.fullmatch(r"/([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)/-/merge_requests/([1-9][0-9]*)/?", parsed.path)
    require(match is not None, "Expected https://HOST/group/project/-/merge_requests/IID")
    assert match is not None
    project, iid = match.groups()
    require(all(p not in (".", "..") for p in project.split("/")), "Invalid project path")
    return parsed.netloc.lower(), project, iid


class GitLab:
    def __init__(self, url: str) -> None:
        self.url = url
        self.host, self.project, self.iid = mr_target(url)

    def call(self, operation: List[str], arguments: List[str]) -> JSON:
        command = ["idev-cli", "code", "mr"] + operation + ["--project", self.project, "--mr", self.iid, "--json"] + arguments
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=120, check=False)
        except subprocess.TimeoutExpired as error:
            raise ReviewError("idev-cli timed out; a write may have completed. Inspect GitLab before retrying.") from error
        require(result.returncode == 0, "idev-cli " + " ".join(operation) + " failed; check CLI authentication/configuration. No automatic retry.")
        try:
            return cast(JSON, json.loads(result.stdout))
        except json.JSONDecodeError as error:
            raise ReviewError("idev-cli returned invalid JSON; inspect a possible write before retrying") from error

    def metadata(self) -> Object:
        data = obj(self.call(["get"], []))
        canonical = urlparse(string(data["web_url"]))
        # Some self-hosted instances advertise HTTP behind an HTTPS proxy.
        if canonical.scheme == "http":
            canonical = canonical._replace(scheme="https")
        require(mr_target(canonical.geturl()) == (self.host, self.project, self.iid), "CLI returned a different GitLab target")
        refs(data)
        return data

    def pages(self, operation: List[str]) -> List[Object]:
        result: List[Object] = []
        seen = set()
        for page in range(1, 10001):
            batch = records(self.call(operation, ["--page", str(page), "--per-page", "100"]))
            signature = json.dumps(batch, sort_keys=True)
            require(not batch or signature not in seen, "CLI pagination repeated a page")
            seen.add(signature)
            result.extend(batch)
            if len(batch) < 100:
                return result
        raise ReviewError("Pagination exceeded 10000 pages")


def refs(metadata: Object) -> Object:
    result = obj(metadata.get("diff_refs"))
    require(set(result) >= {"base_sha", "head_sha", "start_sha"}, "MR has no complete diff refs yet")
    for key in ("base_sha", "head_sha", "start_sha"):
        require(bool(re.fullmatch(r"[a-f0-9]{40,64}", string(result[key]))), "Invalid diff ref " + key)
    return {key: result[key] for key in ("base_sha", "head_sha", "start_sha")}


def snapshot(client: GitLab, output: Path) -> None:
    before = client.metadata()
    diffs = client.pages(["diff"])
    discussions = client.pages(["discussion", "list"])
    notes = client.pages(["note", "list"])
    require(refs(client.metadata()) == refs(before), "MR changed during collection; take another snapshot")
    coverage = ["Diff unavailable for " + string(d["new_path"]) for d in diffs if not d.get("diff") or d.get("too_large") or d.get("collapsed")]
    count = before.get("changes_count")
    if isinstance(count, str) and (count.endswith("+") or (count.isdigit() and int(count) != len(diffs))):
        coverage.append("Server change count differs from the captured diff; verify omitted files")
    data: Object = {"version": 1, "url": client.url, "metadata": before, "diffs": diffs,
                    "discussions": discussions, "notes": notes, "coverage_gaps": coverage}
    write_json(output, data)


def position(f: Finding, diffs: List[Object]) -> Object:
    matches = [d for d in diffs if d.get(f.side + "_path") == f.file]
    require(len(matches) == 1, f.id + ": file missing or ambiguous in captured diff")
    diff = matches[0]
    old = new = None
    for line in string(diff.get("diff")).splitlines():
        hunk = re.match(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
        if hunk:
            old, new = map(int, hunk.groups())
            continue
        if old is None or new is None or not line or line.startswith("\\"):
            continue
        coordinates: Object = {}
        if line.startswith("+"):
            coordinates = {"new_line": new}
            new += 1
        elif line.startswith("-"):
            coordinates = {"old_line": old}
            old += 1
        elif line.startswith(" "):
            coordinates = {"old_line": old, "new_line": new}
            old += 1
            new += 1
        if coordinates.get(f.side + "_line") == f.line:
            return {"old_path": diff["old_path"], "new_path": diff["new_path"], **coordinates}
    raise ReviewError(f.id + ": line is not present in the captured diff")


def fingerprint(f: Finding) -> str:
    return hashlib.sha256((f.file + "\0" + f.key).encode()).hexdigest()[:24]


def marker(key: str) -> str:
    return PREFIX + key + " -->"


def owned_note(notes: List[Object], receipt: Object, expected_marker: str) -> Object:
    matches = [n for n in notes if n.get("id") == receipt.get("note_id")]
    require(len(matches) == 1, "Recorded review note is missing; reconcile the publication ledger")
    note = matches[0]
    require(obj(note.get("author")).get("id") == receipt.get("author_id") and expected_marker in string(note.get("body")),
            "Recorded comment ownership or marker changed")
    return note


def plan(review: Review, snap: Object, ledger: Object, discussions: List[Object], notes: List[Object]) -> List[Object]:
    operations: List[Object] = []
    saved = obj(ledger["findings"])
    indexed = {string(d["id"]): d for d in discussions}
    head = string(refs(obj(snap["metadata"]))["head_sha"])
    for f in review.findings:
        if not eligible(review, f):
            continue
        key = fingerprint(f)
        tag = marker(key)
        body = finding_body(f) + f"\n\nReviewed commit: `{head}`\n\n" + tag
        if f.existing_discussion_id:
            require(f.existing_discussion_id in indexed, "Referenced existing discussion no longer exists")
            operations.append({"kind": "skip", "key": key, "reason": "Already covered by discussion " + f.existing_discussion_id})
            continue
        if key in saved:
            receipt = obj(saved[key])
            discussion_id = string(receipt["discussion_id"])
            require(discussion_id in indexed, "Recorded discussion is missing")
            thread = records(indexed[discussion_id]["notes"])
            note = owned_note(thread, receipt, tag)
            replied = any(not n.get("system") and obj(n.get("author")).get("id") != receipt["author_id"] for n in thread)
            if note.get("resolved") or replied or note["body"] == body:
                operations.append({"kind": "skip", "key": key, "reason": "Resolved, human-replied, or unchanged discussion"})
            elif obj(note.get("position")).get("head_sha") != head:
                operations.append({"kind": "skip", "key": key, "reason": "Existing discussion belongs to an earlier revision; retained"})
            else:
                operations.append({"kind": "update_finding", "key": key, "body": body, **receipt})
        else:
            require(not any(tag in string(n.get("body")) for d in discussions for n in records(d["notes"])),
                    "A matching review marker exists without a receipt; recover the ledger or link that discussion")
            operations.append({"kind": "create_finding", "key": key, "body": body, "position": position(f, records(snap["diffs"]))})
    body = summary_body(review) + f"\nReviewed commit: `{head}`\n\n" + marker("summary")
    if ledger.get("summary"):
        receipt = obj(ledger["summary"])
        note = owned_note(notes, receipt, marker("summary"))
        if note["body"] != body:
            operations.append({"kind": "update_summary", "body": body, **receipt})
    else:
        require(not any(marker("summary") in string(n.get("body")) for n in notes), "Summary exists without its receipt; recover the original ledger")
        operations.append({"kind": "create_summary", "body": body})
    return operations


def execute(client: GitLab, operation: Object, snapshot_refs: Object) -> Object:
    metadata = client.metadata()
    require(metadata.get("state") == "opened", "MR closed during publication")
    require(refs(metadata) == snapshot_refs, "MR changed before publication; stop and review the new revision")
    kind = string(operation["kind"])
    arguments = ["--message", string(operation["body"])]
    if kind == "create_finding":
        for key, value in {**obj(operation["position"]), **snapshot_refs}.items():
            arguments += ["--" + key.replace("_", "-"), str(value)]
        result = obj(client.call(["discussion", "create"], arguments))
        first = records(result["notes"])[0]
        return {"discussion_id": result["id"], "note_id": first["id"], "author_id": obj(first["author"])["id"]}
    if kind == "update_finding":
        threads = client.pages(["discussion", "list"])
        matches = [d for d in threads if d["id"] == operation["discussion_id"]]
        require(len(matches) == 1, "Discussion disappeared before update")
        notes = records(matches[0]["notes"])
        note = owned_note(notes, operation, marker(string(operation["key"])))
        require(not note.get("resolved") and not any(not n.get("system") and obj(n["author"])["id"] != operation["author_id"] for n in notes),
                "Discussion was resolved or received a human reply; prepare a fresh plan")
        client.call(["discussion", "update"], arguments + ["--discussion", string(operation["discussion_id"]), "--note", str(operation["note_id"])])
        return {key: operation[key] for key in ("discussion_id", "note_id", "author_id")}
    if kind == "create_summary":
        result = obj(client.call(["note", "create"], arguments))
        return {"note_id": result["id"], "author_id": obj(result["author"])["id"]}
    require(kind == "update_summary", "Unknown publication operation")
    owned_note(client.pages(["note", "list"]), operation, marker("summary"))
    client.call(["note", "update"], arguments + ["--note", str(operation["note_id"])])
    return {key: operation[key] for key in ("note_id", "author_id")}


def publish(review: Review, snapshot_path: Path, ledger_path: Path, apply: bool) -> None:
    require(review.snapshot_sha256 == digest(snapshot_path), "Review is not bound to this snapshot")
    snap = obj(read_json(snapshot_path))
    require(snap.get("version") == 1, "Unsupported snapshot version")
    for gap in cast(List[str], snap["coverage_gaps"]):
        require(gap in review.coverage_gaps or bool(review.no_verdict_reason), "Review omitted a snapshot coverage gap")
    require(bool(snap["diffs"]) or bool(review.no_verdict_reason), "Empty snapshot needs No Verdict")
    client = GitLab(string(snap["url"]))
    expected_refs = refs(obj(snap["metadata"]))
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with ledger_path.with_suffix(ledger_path.suffix + ".lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ReviewError("Another publisher holds this ledger lock") from error
        ledger = obj(read_json(ledger_path)) if ledger_path.exists() else {"version": 1, "url": client.url, "findings": {}, "summary": None}
        require(ledger.get("version") == 1 and mr_target(string(ledger["url"])) == mr_target(client.url), "Ledger belongs to another MR or version")
        metadata = client.metadata()
        require(metadata.get("state") == "opened", "MR is no longer open")
        require(refs(metadata) == expected_refs, "MR revision changed; take a new snapshot and review again")
        discussions = client.pages(["discussion", "list"])
        notes = client.pages(["note", "list"])
        operations = plan(review, snap, ledger, discussions, notes)
        print(json.dumps({"apply": apply, "operations": operations}, indent=2, ensure_ascii=False))
        if not apply:
            return
        for operation in operations:
            if operation["kind"] == "skip":
                continue
            receipt = execute(client, operation, expected_refs)
            if "finding" in string(operation["kind"]):
                obj(ledger["findings"])[string(operation["key"])] = receipt
            else:
                ledger["summary"] = receipt
            write_json(ledger_path, ledger)
        require(refs(client.metadata()) == expected_refs, "MR changed during publication; posted comments describe the captured commit")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("snapshot", help="Read an MR through idev-cli")
    capture.add_argument("--url", required=True)
    capture.add_argument("--output", type=Path, required=True)
    report = commands.add_parser("render", help="Validate review JSON and write Markdown")
    report.add_argument("--review", type=Path, required=True)
    report.add_argument("--output", type=Path, required=True)
    post = commands.add_parser("publish", help="Plan GitLab comments; --apply performs writes")
    post.add_argument("--review", type=Path, required=True)
    post.add_argument("--snapshot", type=Path, required=True)
    post.add_argument("--ledger", type=Path, required=True)
    post.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "snapshot":
            snapshot(GitLab(args.url), args.output)
        elif args.command == "render":
            render(load_review(args.review), args.output)
        else:
            publish(load_review(args.review), args.snapshot, args.ledger, args.apply)
    except (ReviewError, OSError, ValueError, KeyError, TypeError, IndexError) as error:
        parser.exit(1, "review: " + str(error) + "\n")


if __name__ == "__main__":
    main()
