from __future__ import annotations

import json
import re
import subprocess
from typing import Dict, List, Optional, Protocol, Union, cast
from urllib.parse import urlparse

JSON = Union[None, bool, int, float, str, List["JSON"], Dict[str, "JSON"]]
Object = Dict[str, JSON]


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


def mr_target(url: str) -> tuple[str, str, str]:
    parsed = urlparse(url)
    require(parsed.scheme == "https" and bool(parsed.hostname) and not parsed.username and not parsed.password
            and not parsed.query and not parsed.fragment, "Use an HTTPS MR URL without credentials, query or fragment")
    match = re.fullmatch(r"/([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)/-/merge_requests/([1-9][0-9]*)/?", parsed.path)
    require(match is not None, "Expected https://HOST/group/project/-/merge_requests/IID")
    assert match is not None
    project, iid = match.groups()
    require(all(p not in (".", "..") for p in project.split("/")), "Invalid project path")
    host = parsed.netloc.lower()
    if parsed.port == 443:
        host = host.rsplit(":", 1)[0]
    return host, project, iid


def pr_target(url: str) -> tuple[str, str, str]:
    parsed = urlparse(url)
    require(parsed.scheme == "https" and bool(parsed.hostname) and not parsed.username and not parsed.password
            and not parsed.query and not parsed.fragment and not parsed.port,
            "Use an HTTPS PR URL without credentials, port, query or fragment")
    match = re.fullmatch(r"/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)/?", parsed.path)
    require(match is not None, "Expected https://HOST/owner/repository/pull/NUMBER")
    assert match is not None
    project, number = match.groups()
    require(all(p not in (".", "..") for p in project.split("/")), "Invalid repository path")
    return parsed.netloc.lower(), project.lower(), number


def target_identity(url: str) -> tuple[str, str, str, str]:
    if "/-/merge_requests/" in urlparse(url).path:
        return ("gitlab", *mr_target(url))
    return ("github", *pr_target(url))


class ReviewClient(Protocol):
    url: str

    def metadata(self) -> Object: ...
    def pages(self, operation: List[str]) -> List[Object]: ...
    def write(self, operation: Object, snapshot_refs: Object) -> Object: ...


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

    def write(self, operation: Object, snapshot_refs: Object) -> Object:
        kind = string(operation["kind"])
        arguments = ["--message", string(operation["body"])]
        if kind == "create_finding":
            for key, value in {**obj(operation["position"]), **snapshot_refs}.items():
                arguments += ["--" + key.replace("_", "-"), str(value)]
            result = obj(self.call(["discussion", "create"], arguments))
            first = records(result["notes"])[0]
            return {"discussion_id": result["id"], **receipt(first)}
        if kind == "update_finding":
            self.call(["discussion", "update"], arguments + ["--discussion", string(operation["discussion_id"]), "--note", str(operation["note_id"])])
        elif kind == "create_summary":
            return receipt(obj(self.call(["note", "create"], arguments)))
        else:
            require(kind == "update_summary", "Unknown publication operation")
            self.call(["note", "update"], arguments + ["--note", str(operation["note_id"])])
        return {key: operation[key] for key in ("discussion_id", "note_id", "author_id") if key in operation}


def receipt(note: Object) -> Object:
    require(type(obj(note["author"]).get("id")) is int and cast(int, obj(note["author"])["id"]) > 0,
            "Written comment has no author ID; reconcile before retrying")
    return {"note_id": note["id"], "author_id": obj(note["author"])["id"]}


def inline_anchor(provider: str, position: Object) -> Object:
    if provider == "github":
        left = position.get("new_line") is None
        result = {"path": position.get("new_path"), "side": "LEFT" if left else "RIGHT",
                  "line": position.get("old_line") if left else position.get("new_line")}
        require(isinstance(result["path"], str) and type(result["line"]) is int,
                "GitHub comment anchor unavailable; reconcile the discussion")
        return result
    require(isinstance(position.get("new_path"), str) and isinstance(position.get("old_path"), str)
            and any(type(position.get(key)) is int for key in ("old_line", "new_line")),
            "GitLab comment anchor unavailable; reconcile the discussion")
    return {key: position[key] for key in ("old_path", "new_path", "old_line", "new_line") if position.get(key) is not None}


THREAD_QUERY = """query($owner:String!, $name:String!, $number:Int!, $cursor:String) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      reviewThreads(first:100, after:$cursor) {
        nodes { isResolved isOutdated comments(first:1) { totalCount nodes { databaseId } } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}"""


class GitHub:
    def __init__(self, url: str) -> None:
        self.url = url
        self.host, self.project, self.number = pr_target(url)
        self.repo_path = "repos/" + self.project
        self.pull_path = self.repo_path + "/pulls/" + self.number

    def api(self, method: str, endpoint: str, payload: Optional[Object]) -> JSON:
        command = ["gh", "api", "--hostname", self.host, "--method", method,
                   "-H", "Accept: application/vnd.github+json", endpoint]
        if payload is not None:
            command += ["--input", "-"]
        try:
            result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                                    capture_output=True, text=True, timeout=120, check=False)
        except subprocess.TimeoutExpired as error:
            raise ReviewError("gh timed out; a write may have completed. Inspect GitHub before retrying.") from error
        require(result.returncode == 0, "gh api failed; check CLI authentication, permissions and target. No automatic retry.")
        try:
            data = cast(JSON, json.loads(result.stdout))
        except json.JSONDecodeError as error:
            raise ReviewError("gh returned invalid JSON; inspect a possible write before retrying") from error
        require(not isinstance(data, dict) or not data.get("errors"), "GitHub GraphQL returned errors; no partial result accepted")
        return data

    def rest_pages(self, endpoint: str, max_pages: int) -> List[Object]:
        result: List[Object] = []
        seen = set()
        for page in range(1, max_pages + 1):
            batch = records(self.api("GET", endpoint + f"?per_page=100&page={page}", None))
            signature = json.dumps(batch, sort_keys=True)
            require(not batch or signature not in seen, "GitHub pagination repeated a page")
            seen.add(signature)
            result.extend(batch)
            if len(batch) < 100:
                return result
        if max_pages == 30:
            # GitHub caps PR files at 3000; snapshot compares against changed_files.
            return result
        raise ReviewError("GitHub pagination exceeded its page limit")

    def metadata(self) -> Object:
        data = obj(self.api("GET", self.pull_path, None))
        require(pr_target(string(data["html_url"])) == (self.host, self.project, self.number),
                "CLI returned a different GitHub target")
        base, head = obj(data["base"]), obj(data["head"])
        preliminary: Object = {"diff_refs": {"base_sha": base["sha"], "start_sha": base["sha"], "head_sha": head["sha"]}}
        refs(preliminary)
        comparison = obj(self.api("GET", self.repo_path + "/compare/" + string(base["sha"]) + "..." + string(head["sha"]) + "?per_page=1", None))
        result: Object = {"web_url": data["html_url"], "state": "opened" if data["state"] == "open" else "closed",
                          "title": data["title"], "description": data.get("body"), "changes_count": data["changed_files"],
                          "source_branch": head["ref"], "target_branch": base["ref"],
                          "diff_refs": {"base_sha": obj(comparison["merge_base_commit"])["sha"],
                                        "start_sha": base["sha"], "head_sha": head["sha"]}}
        refs(result)
        return result

    @staticmethod
    def note(data: Object) -> Object:
        side = "old_line" if data.get("side") == "LEFT" else "new_line"
        return {**data, "author": obj(data.get("user") or {}), "system": False,
                "position": {"head_sha": data.get("original_commit_id", data.get("commit_id")),
                             "old_path": data.get("path"), "new_path": data.get("path"), side: data.get("line")}}

    def discussions(self) -> List[Object]:
        comments = self.rest_pages(self.pull_path + "/comments", 10000)
        grouped: Dict[str, List[Object]] = {}
        for comment in comments:
            root = str(comment.get("in_reply_to_id") or comment["id"])
            grouped.setdefault(root, []).append(self.note(comment))
        owner, name = self.project.split("/")
        cursor: JSON = None
        seen = set()
        states: Dict[str, Object] = {}
        for _ in range(10000):
            data = obj(self.api("POST", "graphql", {"query": THREAD_QUERY,
                       "variables": {"owner": owner, "name": name, "number": int(self.number), "cursor": cursor}}))
            pull = obj(obj(obj(data["data"])["repository"])["pullRequest"])
            connection = obj(pull["reviewThreads"])
            for thread in records(connection["nodes"]):
                roots = records(obj(thread["comments"])["nodes"])
                require(len(roots) == 1 and type(roots[0].get("databaseId")) is int, "GitHub thread has no identifiable root")
                require(type(thread.get("isResolved")) is bool and type(thread.get("isOutdated")) is bool,
                        "GitHub thread state is unavailable")
                states[str(roots[0]["databaseId"])] = thread
            page = obj(connection["pageInfo"])
            if not page["hasNextPage"]:
                break
            cursor = string(page["endCursor"])
            require(cursor not in seen, "GitHub thread pagination repeated a cursor")
            seen.add(cursor)
        else:
            raise ReviewError("GitHub thread pagination exceeded its page limit")
        require(set(grouped) == set(states), "GitHub thread/comment lists disagree; capture again before publishing")
        result: List[Object] = []
        for root, notes in grouped.items():
            state = states[root]
            require(len(notes) == obj(state["comments"])["totalCount"], "GitHub thread changed during collection")
            require(any(str(n["id"]) == root for n in notes), "GitHub thread root is missing")
            result.append({"id": root, "notes": [{**n, "resolved": state["isResolved"], "outdated": state["isOutdated"]} for n in notes]})
        for review in self.rest_pages(self.pull_path + "/reviews", 10000):
            if review.get("body"):
                result.append({"id": "review:" + str(review["id"]), "notes": [self.note(review)]})
        return result

    def pages(self, operation: List[str]) -> List[Object]:
        if operation == ["diff"]:
            result: List[Object] = []
            for file in self.rest_pages(self.pull_path + "/files", 30):
                patch = string(file.get("patch") or "")
                added = sum(line.startswith("+") for line in patch.splitlines())
                removed = sum(line.startswith("-") for line in patch.splitlines())
                result.append({"old_path": file.get("previous_filename", file["filename"]), "new_path": file["filename"],
                               "diff": patch, "new_file": file["status"] == "added", "deleted_file": file["status"] == "removed",
                               "renamed_file": file["status"] == "renamed",
                               "too_large": added != file["additions"] or removed != file["deletions"]})
            return result
        if operation == ["discussion", "list"]:
            return self.discussions()
        require(operation == ["note", "list"], "Unknown GitHub read operation")
        return [self.note(n) for n in self.rest_pages(self.repo_path + "/issues/" + self.number + "/comments", 10000)]

    def write(self, operation: Object, snapshot_refs: Object) -> Object:
        kind = string(operation["kind"])
        payload: Object = {"body": operation["body"]}
        if kind == "create_finding":
            pos = obj(operation["position"])
            payload.update(commit_id=snapshot_refs["head_sha"], **inline_anchor("github", pos))
            note = self.note(obj(self.api("POST", self.pull_path + "/comments", payload)))
            return {"discussion_id": str(note["id"]), **receipt(note)}
        if kind == "create_summary":
            note = self.note(obj(self.api("POST", self.repo_path + "/issues/" + self.number + "/comments", payload)))
            return receipt(note)
        require(kind in ("update_finding", "update_summary"), "Unknown GitHub write operation")
        require(type(operation.get("note_id")) is int and cast(int, operation["note_id"]) > 0, "Invalid GitHub comment ID")
        endpoint = "/pulls/comments/" if kind == "update_finding" else "/issues/comments/"
        self.api("PATCH", self.repo_path + endpoint + str(operation["note_id"]), payload)
        return {key: operation[key] for key in ("discussion_id", "note_id", "author_id") if key in operation}


def refs(metadata: Object) -> Object:
    result = obj(metadata.get("diff_refs"))
    require(set(result) >= {"base_sha", "head_sha", "start_sha"}, "Review target has no complete diff refs yet")
    for key in ("base_sha", "head_sha", "start_sha"):
        require(bool(re.fullmatch(r"[a-f0-9]{40,64}", string(result[key]))), "Invalid diff ref " + key)
    return {key: result[key] for key in ("base_sha", "head_sha", "start_sha")}
