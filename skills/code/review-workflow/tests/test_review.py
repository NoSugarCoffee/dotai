import contextlib
import copy
import dataclasses
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "review.py"
SPEC = importlib.util.spec_from_file_location("review", MODULE_PATH)
review = importlib.util.module_from_spec(SPEC)
sys.modules["review"] = review
SPEC.loader.exec_module(review)

REFS = {"base_sha": "a" * 40, "start_sha": "b" * 40, "head_sha": "c" * 40}
URL = "https://gitlab.example.test/team/project/-/merge_requests/42"
METADATA = {"web_url": URL, "diff_refs": REFS, "state": "opened"}
DIFF = {"old_path": "old.py", "new_path": "new.py", "diff": "@@ -10,2 +10,3 @@\n unchanged\n-removed\n+added\n+extra\n"}


def record():
    return {
        "version": 1, "mode": "routine", "scope": "Example MR", "snapshot_sha256": None,
        "summary": "Reviewed changed behavior.", "no_verdict_reason": None, "coverage_gaps": [],
        "stages": {"analysis": "complete", "validation": "complete"},
        "findings": [{
            "id": "bug-1", "key": "lost-update", "file": "new.py", "side": "new", "line": 11,
            "title": "An update is lost", "evidence": "The branch discards the value.",
            "impact": "Saved state is stale.", "fix": "Preserve the value.", "source": "routine",
            "severity": "important", "confidence": 90, "status": "validated", "final_severity": "important",
            "audit": "not_run", "audit_reason": None, "dismissal_stage": None, "dismissal_reason": None, "existing_discussion_id": None,
        }],
    }


class FakeGitLab:
    def __init__(self):
        self.url = URL
        self.meta = copy.deepcopy(METADATA)
        self.discussions = []
        self.notes = []
        self.writes = []
        self.fail_summary = False

    def metadata(self):
        return self.meta

    def pages(self, operation):
        return self.discussions if operation == ["discussion", "list"] else self.notes

    def call(self, operation, arguments):
        self.writes.append((operation, arguments))
        body = arguments[arguments.index("--message") + 1]
        if operation == ["discussion", "create"]:
            note = {"id": 100, "author": {"id": 7}, "body": body, "resolved": False,
                    "position": {"head_sha": REFS["head_sha"]}}
            result = {"id": "thread1", "notes": [note]}
            self.discussions.append(result)
            return result
        if operation == ["note", "create"]:
            if self.fail_summary:
                raise review.ReviewError("Summary failed")
            result = {"id": 200, "author": {"id": 7}, "body": body}
            self.notes.append(result)
            return result
        if operation == ["note", "update"]:
            self.notes[0]["body"] = body
            return self.notes[0]
        if operation == ["discussion", "update"]:
            self.discussions[0]["notes"][0]["body"] = body
            return self.discussions[0]["notes"][0]
        raise AssertionError(operation)


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.snapshot = self.root / "snapshot.json"
        self.ledger = self.root / "publication.json"
        review.write_json(self.snapshot, {"version": 1, "url": URL, "metadata": METADATA,
                                         "diffs": [DIFF], "coverage_gaps": []})
        self.data = record()
        self.data["snapshot_sha256"] = review.digest(self.snapshot)
        self.client = FakeGitLab()

    def load(self):
        path = self.root / "review.json"
        review.write_json(path, self.data)
        return review.load_review(path)

    def publish(self, apply=True):
        with patch.object(review, "GitLab", return_value=self.client), contextlib.redirect_stdout(io.StringIO()):
            review.publish(self.load(), self.snapshot, self.ledger, apply)

    def test_added_deleted_context_and_renamed_positions(self):
        f = self.load().findings[0]
        self.assertEqual(review.position(f, [DIFF]), {"old_path": "old.py", "new_path": "new.py", "new_line": 11})
        deleted = dataclasses.replace(f, file="old.py", side="old")
        self.assertEqual(review.position(deleted, [DIFF])["old_line"], 11)
        self.assertNotIn("new_line", review.position(deleted, [DIFF]))
        context = dataclasses.replace(f, line=10)
        self.assertEqual(review.position(context, [DIFF])["old_line"], 10)
        with self.assertRaises(review.ReviewError):
            review.position(dataclasses.replace(f, line=99), [DIFF])

    def test_multihunk_context_coordinates(self):
        diff = {**DIFF, "diff": "@@ -1 +1,2 @@\n one\n+new\n@@ -10 +11 @@\n ten\n"}
        self.assertEqual(review.position(self.load().findings[0], [diff])["old_line"], 10)

    def test_dry_run_and_repeated_publication(self):
        self.publish(False)
        self.assertFalse(self.client.writes)
        self.publish()
        self.assertEqual(len(self.client.writes), 2)
        self.publish()
        self.assertEqual(len(self.client.writes), 2)

    def test_summary_update_uses_same_note(self):
        self.publish()
        self.data["summary"] = "Rechecked the evidence."
        self.publish()
        self.assertEqual(self.client.writes[-1][0], ["note", "update"])
        self.assertEqual(len(self.client.notes), 1)

    def test_stale_head_prevents_all_writes(self):
        self.client.meta["diff_refs"]["head_sha"] = "d" * 40
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.assertFalse(self.client.writes)

    def test_push_between_writes_keeps_receipt(self):
        original_call = self.client.call

        def call(operation, args):
            result = original_call(operation, args)
            self.client.meta["diff_refs"]["head_sha"] = "d" * 40
            return result

        self.client.call = call
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.assertEqual(len(self.client.writes), 1)
        self.assertEqual(len(review.obj(review.read_json(self.ledger))["findings"]), 1)

    def test_partial_failure_resumes_without_duplicate_inline(self):
        self.client.fail_summary = True
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.client.fail_summary = False
        self.publish()
        self.assertEqual(len(self.client.discussions), 1)
        self.assertEqual(len(self.client.notes), 1)

    def test_human_reply_and_resolution_are_preserved(self):
        for resolved in (True, False):
            with self.subTest(resolved=resolved):
                self.client = FakeGitLab()
                if self.ledger.exists():
                    self.ledger.unlink()
                self.publish()
                note = self.client.discussions[0]["notes"][0]
                note["resolved"] = resolved
                if not resolved:
                    self.client.discussions[0]["notes"].append({"id": 101, "author": {"id": 8}, "body": "We discussed this"})
                self.data["findings"][0]["fix"] += " Updated advice."
                self.publish()
                self.assertEqual(len(self.client.writes), 2)

    def test_marker_without_receipt_fails_before_writes(self):
        f = self.load().findings[0]
        self.client.discussions = [{"id": "copied", "notes": [{"id": 9, "body": review.marker(review.fingerprint(f)), "author": {"id": 99}}]}]
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.assertFalse(self.client.writes)

    def test_wrong_author_cannot_be_updated(self):
        self.publish()
        self.client.discussions[0]["notes"][0]["author"]["id"] = 99
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.assertEqual(len(self.client.writes), 2)

    def test_changed_snapshot_and_wrong_ledger_target_fail(self):
        review.write_json(self.ledger, {"version": 1, "url": URL.replace("42", "43"), "findings": {}, "summary": None})
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.ledger.unlink()
        self.snapshot.write_text(self.snapshot.read_text() + "\n")
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.assertFalse(self.client.writes)

    def test_deep_failed_audit_is_incomplete_and_not_published(self):
        self.data["mode"] = "deep"
        self.data["stages"] = {name: "complete" for name in review.REQUIRED["deep"]}
        self.data["stages"]["audit"] = "failed"
        self.data["findings"][0]["final_severity"] = None
        value = self.load()
        self.assertEqual(review.verdict(value), "INCOMPLETE")
        self.publish()
        self.assertFalse(self.client.discussions)
        self.assertIn("INCOMPLETE", self.client.notes[0]["body"])
        review.render(value, self.root)
        self.assertIn("Awaiting verification", (self.root / "review-report.md").read_text())

    def test_empty_scope_and_dismissed_evidence_render(self):
        self.data["findings"][0].update(status="dismissed", final_severity=None, dismissal_stage="validation", dismissal_reason="Caller protects the path")
        review.render(self.load(), self.root)
        self.assertIn("Caller protects", (self.root / "review-report.md").read_text())
        self.assertEqual((self.root / "review-inline-comments.md").read_text(), "")
        self.data.update(findings=[], no_verdict_reason="The requested diff is empty", stages={})
        self.assertEqual(review.verdict(self.load()), "NO VERDICT")

    def test_invalid_contract_is_rejected(self):
        for field, value in (("status", "validted"), ("line", True), ("final_severity", "blocker"), ("confidence", 101)):
            original = self.data["findings"][0][field]
            self.data["findings"][0][field] = value
            with self.subTest(field=field), self.assertRaises(review.ReviewError):
                self.load()
            self.data["findings"][0][field] = original

    def test_explicit_project_and_no_shell_interpolation(self):
        body = "Literal `command` $(other)\nsecond line"
        with patch.object(review.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "{}", "")) as run:
            review.GitLab(URL).call(["note", "create"], ["--message", body])
        args, kwargs = run.call_args
        self.assertIn("team/project", args[0])
        self.assertEqual(args[0][-1], body)
        self.assertNotIn("shell", kwargs)

    def test_pagination_and_repeated_page_detection(self):
        client = review.GitLab(URL)
        first = [{"id": n} for n in range(100)]
        with patch.object(client, "call", side_effect=[first, [{"id": 100}]]):
            self.assertEqual(len(client.pages(["note", "list"])), 101)
        with patch.object(client, "call", return_value=first), self.assertRaises(review.ReviewError):
            client.pages(["note", "list"])

    def test_wrong_host_and_malformed_url_rejected(self):
        with patch.object(review.GitLab, "call", return_value={**METADATA, "web_url": URL.replace("example.test", "other.test")}):
            with self.assertRaises(review.ReviewError):
                review.GitLab(URL).metadata()
        for url in (URL + "?x=y", "http://" + URL[8:], URL.replace("42", "0")):
            with self.subTest(url=url), self.assertRaises(review.ReviewError):
                review.mr_target(url)

    def test_server_http_canonical_url_preserves_target_identity(self):
        with patch.object(review.GitLab, "call", return_value={**METADATA, "web_url": URL.replace("https://", "http://")}):
            self.assertEqual(review.GitLab(URL).metadata()["diff_refs"], REFS)
        wrong = URL.replace("https://", "http://").replace("/42", "/43")
        with patch.object(review.GitLab, "call", return_value={**METADATA, "web_url": wrong}), self.assertRaises(review.ReviewError):
            review.GitLab(URL).metadata()


if __name__ == "__main__":
    unittest.main()
