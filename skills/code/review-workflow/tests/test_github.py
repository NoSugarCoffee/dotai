import contextlib
import copy
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from test_review import DIFF, REFS, record, review
from providers import GitHub, pr_target

URL = "https://github.com/team/project/pull/42"
USER = {"id": 7, "login": "reviewer"}


class FakeGitHub(GitHub):
    def __init__(self):
        super().__init__(URL)
        self.meta = {"html_url": URL, "state": "open", "title": "Example", "body": "Intent", "changed_files": 1,
                     "base": {"sha": REFS["start_sha"], "ref": "main"},
                     "head": {"sha": REFS["head_sha"], "ref": "topic"}}
        self.files = [{"filename": "new.py", "previous_filename": "old.py", "status": "renamed",
                       "patch": DIFF["diff"], "additions": 2, "deletions": 1}]
        self.comments = []
        self.notes = []
        self.reviews = []
        self.states = {}
        self.writes = []
        self.fail_summary = False
        self.after_write = None

    def api(self, method, endpoint, payload):
        if method == "GET":
            if endpoint == self.pull_path:
                return copy.deepcopy(self.meta)
            if "/compare/" in endpoint:
                return {"merge_base_commit": {"sha": REFS["base_sha"]}}
            endpoint, query = endpoint.split("?", 1)
            page = int(query.split("page=")[-1])
            items = {self.pull_path + "/files": self.files,
                     self.pull_path + "/comments": self.comments,
                     self.pull_path + "/reviews": self.reviews,
                     self.repo_path + "/issues/42/comments": self.notes}[endpoint]
            return copy.deepcopy(items[(page - 1) * 100:page * 100])
        if endpoint == "graphql":
            nodes = []
            for comment in self.comments:
                if "in_reply_to_id" not in comment:
                    count = 1 + sum(c.get("in_reply_to_id") == comment["id"] for c in self.comments)
                    resolved, outdated = self.states.get(comment["id"], (False, False))
                    nodes.append({"isResolved": resolved, "isOutdated": outdated,
                                  "comments": {"totalCount": count, "nodes": [{"databaseId": comment["id"]}]}})
            return {"data": {"repository": {"pullRequest": {"reviewThreads": {
                "nodes": nodes, "pageInfo": {"hasNextPage": False, "endCursor": None}}}}}}
        self.writes.append((method, endpoint, copy.deepcopy(payload)))
        if method == "POST":
            if endpoint == self.pull_path + "/comments":
                note = {"id": 100 + len(self.comments), "user": USER, **payload,
                        "original_commit_id": payload["commit_id"]}
                self.comments.append(note)
            else:
                if self.fail_summary:
                    raise review.ReviewError("Summary failed")
                note = {"id": 200 + len(self.notes), "user": USER, **payload}
                self.notes.append(note)
        elif method == "PATCH":
            comment_id = int(endpoint.rsplit("/", 1)[1])
            note = next(n for n in self.comments + self.notes if n["id"] == comment_id)
            note.update(payload)
        else:
            raise AssertionError((method, endpoint))
        if self.after_write:
            self.after_write()
        return copy.deepcopy(note)


class GitHubTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.snapshot = self.root / "snapshot.json"
        self.ledger = self.root / "publication.json"
        self.client = FakeGitHub()
        self.data = record()
        self.capture()

    def capture(self):
        review.snapshot(self.client, self.snapshot)
        self.data["snapshot_sha256"] = review.digest(self.snapshot)

    def publish(self, apply=True):
        path = self.root / "review.json"
        review.write_json(path, self.data)
        with patch.object(review, "GitHub", return_value=self.client), contextlib.redirect_stdout(io.StringIO()):
            review.publish(review.load_review(path), self.snapshot, self.ledger, apply)

    def test_routes_url_and_uses_merge_base_not_base_tip(self):
        self.assertIsInstance(review.client_for(URL), GitHub)
        self.assertIsInstance(review.client_for("https://gitlab.test/team/project/-/merge_requests/42"), review.GitLab)
        self.assertEqual(pr_target(URL.replace("team", "Team")), pr_target(URL))
        self.assertEqual(review.read_json(self.snapshot)["metadata"]["diff_refs"], REFS)
        for url in (URL + "?a=b", URL + "#comment", URL.replace("https:", "http:"), URL.replace("42", "0"),
                    URL.replace("team/project", "../project"), URL.replace("github.com", "user@github.com")):
            with self.subTest(url=url), self.assertRaises(review.ReviewError):
                pr_target(url)

    def test_dry_run_create_and_idempotent_repeat(self):
        self.publish(False)
        self.assertEqual(self.client.writes, [])
        self.publish()
        self.assertEqual(len(self.client.writes), 2)
        payload = self.client.writes[0][2]
        self.assertEqual((payload["path"], payload["side"], payload["line"], payload["commit_id"]),
                         ("new.py", "RIGHT", 11, REFS["head_sha"]))
        self.publish()
        self.assertEqual(len(self.client.writes), 2)
        ledger = review.read_json(self.ledger)
        self.assertEqual(next(iter(ledger["findings"].values()))["discussion_id"], "100")

    def test_deletion_and_old_context_on_renamed_file(self):
        for line, side, expected in ((11, "LEFT", 11), (10, "RIGHT", 10)):
            with self.subTest(line=line):
                self.client = FakeGitHub()
                if self.ledger.exists():
                    self.ledger.unlink()
                self.data["findings"][0].update(file="old.py", side="old", line=line)
                self.publish()
                payload = self.client.writes[0][2]
                self.assertEqual((payload["path"], payload["side"], payload["line"]), ("new.py", side, expected))

    def test_updates_own_comment_and_summary_in_place(self):
        self.publish()
        self.data["findings"][0]["fix"] = "More precise repair"
        self.data["summary"] = "Updated summary"
        self.publish()
        self.assertEqual([call[0] for call in self.client.writes], ["POST", "POST", "PATCH", "PATCH"])
        self.assertEqual((len(self.client.comments), len(self.client.notes)), (1, 1))

    def test_moved_finding_preserves_old_comment_and_reuses_history(self):
        self.publish()
        original = copy.deepcopy(self.client.comments[0])
        self.data["findings"][0]["line"] = 12
        self.publish()
        self.assertEqual(self.client.comments[0], original)
        self.assertEqual(self.client.comments[1]["line"], 12)
        self.publish()
        self.assertEqual(len(self.client.comments), 2)
        self.data["findings"][0].update(line=11, fix="More precise repair")
        self.publish()
        self.assertEqual(len(self.client.comments), 2)
        self.assertIn("More precise repair", self.client.comments[0]["body"])

    def test_side_change_at_same_line_creates_left_anchor(self):
        self.client.files[0]["previous_filename"] = "new.py"
        self.capture()
        self.publish()
        self.data["findings"][0]["side"] = "old"
        self.publish()
        self.assertEqual([n["side"] for n in self.client.comments], ["RIGHT", "LEFT"])
        self.assertEqual([n["line"] for n in self.client.comments], [11, 11])

    def test_resolution_after_planning_prevents_replacement(self):
        self.publish()
        self.data["findings"][0]["line"] = 12
        original = self.client.discussions
        calls = 0
        def discussions():
            nonlocal calls
            calls += 1
            if calls == 2:
                self.client.states[100] = (True, False)
            return original()
        with patch.object(self.client, "discussions", side_effect=discussions), self.assertRaises(review.ReviewError):
            self.publish()
        self.assertEqual(len(self.client.comments), 1)

    def test_deleted_authors_are_captured_but_never_owned(self):
        self.publish()
        self.client.comments.append({"id": 101, "body": "Deleted author reply", "user": None, "in_reply_to_id": 100})
        self.client.notes.append({"id": 201, "body": "Deleted author comment", "user": None})
        self.capture()
        captured = review.read_json(self.snapshot)
        self.assertEqual(captured["discussions"][0]["notes"][1]["author"], {})
        self.assertEqual(captured["notes"][1]["author"], {})
        self.data["findings"][0]["fix"] = "Updated repair"
        self.publish()
        self.assertEqual(len(self.client.writes), 2)
        self.client.comments[0]["user"] = None
        with self.assertRaises(review.ReviewError):
            self.publish()

    def test_human_reply_resolved_and_outdated_threads_are_preserved(self):
        for state in ("reply", "resolved", "outdated"):
            with self.subTest(state=state):
                self.client = FakeGitHub()
                if self.ledger.exists():
                    self.ledger.unlink()
                self.publish()
                if state == "reply":
                    self.client.comments.append({"id": 101, "body": "Discussion", "user": {"id": 8}, "in_reply_to_id": 100})
                else:
                    self.client.states[100] = (state == "resolved", state == "outdated")
                self.data["findings"][0]["fix"] += " Updated"
                self.publish()
                self.assertEqual(len(self.client.writes), 2)

    def test_closed_changed_head_and_changed_base_prevent_writes(self):
        for change in ("head", "base", "closed"):
            with self.subTest(change=change):
                self.client = FakeGitHub()
                if change == "closed":
                    self.client.meta["state"] = "closed"
                else:
                    self.client.meta[change]["sha"] = "d" * 40
                with self.assertRaises(review.ReviewError):
                    self.publish()
                self.assertEqual(self.client.writes, [])

    def test_push_between_writes_keeps_receipt(self):
        def push():
            self.client.meta["head"]["sha"] = "d" * 40
        self.client.after_write = push
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.assertEqual(len(self.client.writes), 1)
        self.assertEqual(len(review.read_json(self.ledger)["findings"]), 1)

    def test_partial_failure_can_resume_without_duplicate_finding(self):
        self.client.fail_summary = True
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.client.fail_summary = False
        self.publish()
        self.assertEqual((len(self.client.comments), len(self.client.notes)), (1, 1))

    def test_no_overwrite_without_matching_author_and_receipt(self):
        self.publish()
        self.client.comments[0]["user"] = {"id": 999}
        self.data["findings"][0]["fix"] = "Changed"
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.ledger.unlink()
        with self.assertRaises(review.ReviewError):
            self.publish()
        self.assertEqual(len(self.client.writes), 2)

    def test_missing_truncated_and_omitted_files_are_coverage_gaps(self):
        self.client.files[0]["patch"] = "@@ -10 +10 @@\n-old\n+new\n"
        self.client.files.append({"filename": "binary.dat", "status": "added", "additions": 0, "deletions": 0})
        self.client.meta["changed_files"] = 3001
        self.capture()
        gaps = review.read_json(self.snapshot)["coverage_gaps"]
        self.assertEqual(len(gaps), 3)
        self.data.update(coverage_gaps=gaps, findings=[])
        self.publish()
        self.assertIn("INCOMPLETE", self.client.notes[0]["body"])

    def test_rest_pagination_collects_replies_and_reviews(self):
        self.publish()
        self.client.comments += [{"id": n, "body": "reply", "user": {"id": 8}, "in_reply_to_id": 100} for n in range(1000, 1101)]
        self.client.reviews.append({"id": 900, "user": USER, "body": "Overall review"})
        threads = self.client.discussions()
        self.assertEqual(len(threads[0]["notes"]), 102)
        self.assertEqual(threads[1]["id"], "review:900")

    def test_thread_state_pagination_and_mismatch_stop(self):
        comments = [{"id": n, "body": "note", "user": USER} for n in (1, 2)]
        def page(root, more, cursor):
            return {"data": {"repository": {"pullRequest": {"reviewThreads": {
                "nodes": [{"isResolved": False, "isOutdated": False,
                           "comments": {"totalCount": 1, "nodes": [{"databaseId": root}]}}],
                "pageInfo": {"hasNextPage": more, "endCursor": cursor}}}}}}
        with patch.object(self.client, "rest_pages", side_effect=[comments, []]), patch.object(self.client, "api", side_effect=[page(1, True, "next"), page(2, False, None)]) as api:
            self.assertEqual(len(self.client.discussions()), 2)
            self.assertEqual(api.call_args_list[1].args[2]["variables"]["cursor"], "next")
        with patch.object(self.client, "rest_pages", return_value=comments), patch.object(self.client, "api", return_value=page(1, False, None)), self.assertRaises(review.ReviewError):
            self.client.discussions()

    def test_metadata_rejects_wrong_target_and_missing_refs(self):
        self.client.meta["html_url"] = URL.replace("42", "99")
        with self.assertRaises(review.ReviewError):
            self.client.metadata()
        self.client.meta["html_url"] = URL
        self.client.meta["head"]["sha"] = "not-a-sha"
        with self.assertRaises(review.ReviewError):
            self.client.metadata()

    def test_cli_uses_explicit_host_and_literal_json_stdin(self):
        payload = {"body": "`command` $(other)\nsecond line", "line": 12}
        client = GitHub("https://github.example.test/team/project/pull/42")
        with patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "{}", "")) as run:
            client.api("POST", client.pull_path + "/comments", payload)
        args, kwargs = run.call_args
        self.assertIn("github.example.test", args[0])
        self.assertEqual(json.loads(kwargs["input"]), payload)
        self.assertNotIn("shell", kwargs)
        self.assertNotIn(payload["body"], args[0])

    def test_graphql_errors_and_timeout_are_not_retried(self):
        client = GitHub(URL)
        for result in (subprocess.CompletedProcess([], 0, '{"errors":[{"message":"denied"}],"data":{}}', ""),
                       subprocess.CompletedProcess([], 0, 'not JSON', ""),
                       subprocess.CompletedProcess([], 1, '', "private error")):
            with patch.object(subprocess, "run", return_value=result) as run, self.assertRaises(review.ReviewError):
                client.api("POST", "graphql", {})
            self.assertEqual(run.call_count, 1)
        with patch.object(subprocess, "run", side_effect=subprocess.TimeoutExpired("gh", 120)) as run, self.assertRaises(review.ReviewError):
            client.api("POST", client.pull_path + "/comments", {"body": "finding"})
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
