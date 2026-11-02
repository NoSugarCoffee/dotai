#!/usr/bin/env python3
"""Fill one credential field on an ego-browser page without the secret reaching the caller.

The caller names a field and a selector; this script picks the login by the page's own URL,
reads the value from whichever password store the machine has, and types it into the page.
Only the item name, field and selector are ever printed.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit

ZSHRC_LOCAL = Path.home() / ".zshrc-local"
OP_VAULT = "agent"
URL_MARK = "CF_URL="
FILLED_MARK = "CF_FILLED"


class CredentialFillError(Exception):
    """A failure whose message is safe to print: it never carries a secret."""


class NoStoreError(CredentialFillError):
    pass


class NoMatchError(CredentialFillError):
    pass


class AmbiguousMatchError(CredentialFillError):
    pass


class FillError(CredentialFillError):
    pass


class FieldKind(Enum):
    USERNAME = "username"
    PASSWORD = "password"
    TOTP = "totp"
    CUSTOM = "custom"


@dataclass(frozen=True)
class Field:
    kind: FieldKind
    custom_name: str

    @property
    def label(self) -> str:
        return f"custom:{self.custom_name}" if self.kind is FieldKind.CUSTOM else self.kind.value


@dataclass(frozen=True)
class LoginRef:
    item_id: str
    name: str
    uris: tuple[str, ...]


def parse_field(text: str) -> Field:
    if text.startswith("custom:"):
        name = text.removeprefix("custom:")
        if not name:
            raise argparse.ArgumentTypeError("custom: needs a field name, e.g. custom:sysAccount")
        return Field(FieldKind.CUSTOM, name)
    try:
        return Field(FieldKind(text), "")
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            f"unknown field {text!r}; use username, password, totp or custom:<name>"
        ) from error


def select_login(refs: list[LoginRef], page_url: str) -> LoginRef:
    """Hostname first; on a tie, the item whose URI path also matches. Never guess."""
    page = urlsplit(page_url)
    if not page.hostname:
        raise NoMatchError(f"page URL has no hostname: {page_url.split('?')[0]}")
    by_host = [ref for ref in refs if any(urlsplit(uri).hostname == page.hostname for uri in ref.uris)]
    if not by_host:
        raise NoMatchError(f"no login has a URL on {page.hostname}")
    if len(by_host) == 1:
        return by_host[0]
    by_path = [
        ref
        for ref in by_host
        if any(urlsplit(uri).hostname == page.hostname and urlsplit(uri).path == page.path for uri in ref.uris)
    ]
    if len(by_path) == 1:
        return by_path[0]
    names = ", ".join(sorted(ref.name for ref in (by_path or by_host)))
    raise AmbiguousMatchError(f"several logins match {page.hostname}{page.path}: {names}")


STORE_KEYS = ("OP_SERVICE_ACCOUNT_TOKEN", "BW_SESSION")


def spawn(args: list[str], *, env: dict[str, str], stdin: str | None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, input=stdin, capture_output=True, text=True, env=env, check=False)
    except FileNotFoundError as error:
        raise CredentialFillError(f"`{args[0]}` is not installed or not on PATH") from error


def cli_value(output: str) -> str:
    """Drop only the line ending the CLI adds; a credential's own leading or trailing spaces are kept."""
    return output.removesuffix("\n").removesuffix("\r")


def run_quiet(args: list[str], *, env: dict[str, str], stdin: str | None) -> str:
    """Run a store or browser command; on failure report only the command name, never its output."""
    result = spawn(args, env=env, stdin=stdin)
    if result.returncode != 0:
        raise CredentialFillError(f"`{args[0]} {args[1] if len(args) > 1 else ''}` exited {result.returncode}")
    return result.stdout


class Store(Protocol):
    def list_logins(self, hostname: str) -> list[LoginRef]: ...

    def read(self, ref: LoginRef, field: Field) -> str: ...


class BitwardenStore:
    """`bw list items` prints decrypted secrets, so its output is parsed here and never forwarded."""

    def __init__(self, env: dict[str, str]) -> None:
        self._env = env

    def list_logins(self, hostname: str) -> list[LoginRef]:
        items = json.loads(run_quiet(["bw", "list", "items", "--search", hostname], env=self._env, stdin=None))
        return [
            LoginRef(
                item_id=item["id"],
                name=item["name"],
                uris=tuple(uri["uri"] for uri in (item.get("login") or {}).get("uris") or [] if uri.get("uri")),
            )
            for item in items
        ]

    def read(self, ref: LoginRef, field: Field) -> str:
        if field.kind is FieldKind.CUSTOM:
            item = json.loads(run_quiet(["bw", "get", "item", ref.item_id], env=self._env, stdin=None))
            values = [entry["value"] for entry in item.get("fields") or [] if entry.get("name") == field.custom_name]
            if len(values) != 1:
                raise NoMatchError(f"{ref.name!r} has no single custom field {field.custom_name!r}")
            return values[0]
        return cli_value(run_quiet(["bw", "get", field.kind.value, ref.item_id], env=self._env, stdin=None))


class OnePasswordStore:
    def __init__(self, env: dict[str, str]) -> None:
        self._env = env

    def list_logins(self, hostname: str) -> list[LoginRef]:
        items = json.loads(
            run_quiet(
                ["op", "item", "list", "--vault", OP_VAULT, "--categories", "Login", "--format", "json"],
                env=self._env,
                stdin=None,
            )
        )
        return [
            LoginRef(item_id=item["id"], name=item["title"], uris=tuple(url["href"] for url in item.get("urls") or []))
            for item in items
        ]

    def read(self, ref: LoginRef, field: Field) -> str:
        base = ["op", "item", "get", ref.item_id, "--vault", OP_VAULT]
        if field.kind is FieldKind.TOTP:
            return cli_value(run_quiet([*base, "--otp"], env=self._env, stdin=None))
        label = field.custom_name if field.kind is FieldKind.CUSTOM else field.kind.value
        return cli_value(run_quiet([*base, "--fields", f"label={label}", "--reveal"], env=self._env, stdin=None))


def store_env() -> dict[str, str]:
    """The store keys live in ~/.zshrc-local; pick them up when this shell has not sourced it."""
    env = dict(os.environ)
    if env.get("OP_SERVICE_ACCOUNT_TOKEN") or env.get("BW_SESSION") or not ZSHRC_LOCAL.exists():
        return env
    dump = subprocess.run(
        ["zsh", "-c", f'source "{ZSHRC_LOCAL}" >/dev/null 2>&1; env -0'],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    for entry in dump.split("\0"):
        key, _, value = entry.partition("=")
        if key in STORE_KEYS and value:
            env[key] = value
    return env


def choose_store(env: dict[str, str]) -> Store:
    # A machine sets up one store. If both keys are present, 1Password wins: without its
    # service-account token `op` prompts through the desktop app, so its presence is deliberate.
    if env.get("OP_SERVICE_ACCOUNT_TOKEN"):
        return OnePasswordStore(env)
    if env.get("BW_SESSION"):
        return BitwardenStore(env)
    raise NoStoreError(
        "neither OP_SERVICE_ACCOUNT_TOKEN nor BW_SESSION is set; see 'Agent credentials' in the dotai README"
    )


def space_literal(space: str) -> str:
    return space if space.isdigit() else json.dumps(space)


class EgoPage:
    def __init__(self, space: str, page: str, env: dict[str, str]) -> None:
        self._space = space
        self._page = page
        self._env = env

    def url(self) -> str:
        script = (
            f"const task = await taskSpace({space_literal(self._space)});\n"
            f"console.log('{URL_MARK}' + await task.page({json.dumps(self._page)}).url());\n"
        )
        result = spawn(["ego-browser", "nodejs"], env=self._env, stdin=script)
        marked = [line.removeprefix(URL_MARK) for line in ego_output(result) if line.startswith(URL_MARK)]
        if result.returncode != 0 or not marked:
            raise CredentialFillError(f"could not read the URL of page {self._page} in space {self._space}")
        return marked[-1]

    def fill(self, selector: str, value: str, expected_host: str, submit: str) -> None:
        """The value travels base64-encoded on stdin (not argv, which `ps` shows) and is decoded in the
        browser process. The host is checked right before typing and again before submitting. The two
        cannot be one atomic step, because login inputs often sit in cross-origin frames, so a navigation
        landing inside that window fails the second check and nothing is submitted."""
        encoded = base64.b64encode(value.encode()).decode()
        script = (
            f"const task = await taskSpace({space_literal(self._space)});\n"
            f"const page = task.page({json.dumps(self._page)});\n"
            f"const expected = {json.dumps(expected_host)};\n"
            "const assertHost = async () => {\n"
            "  const host = new URL(await page.url()).hostname;\n"
            "  if (host !== expected) throw new Error('page moved to ' + host);\n"
            "};\n"
            "await assertHost();\n"
            f"await page.fill({json.dumps(selector)}, Buffer.from('{encoded}', 'base64').toString());\n"
            "await assertHost();\n"
            + (f"await page.click({json.dumps(submit)}, {{ label: 'submit' }});\n" if submit else "")
            + f"console.log('{FILLED_MARK}');\n"
        )
        result = spawn(["ego-browser", "nodejs"], env=self._env, stdin=script)
        lines = ego_output(result)
        if result.returncode != 0 or FILLED_MARK not in lines:
            reason = scrub(lines[-1:] or ["no output"], value, encoded)
            raise FillError(f"ego-browser could not fill {selector}: {reason}")


def ego_output(result: subprocess.CompletedProcess[str]) -> list[str]:
    """ego-browser writes console.log to stderr when it is not on a terminal, so read both streams."""
    return [line.strip() for line in (result.stdout + "\n" + result.stderr).splitlines() if line.strip()]


def scrub(lines: list[str], *secrets: str) -> str:
    text = " ".join(lines)
    for secret in secrets:
        if secret:
            text = text.replace(secret, "***")
    return text[:300]


def fill_credential(space: str, page: str, selector: str, field: Field, submit: str) -> str:
    env = store_env()
    store = choose_store(env)
    # The browser needs no vault access, so it does not inherit the store keys.
    browser = EgoPage(space, page, {key: value for key, value in env.items() if key not in STORE_KEYS})
    page_url = browser.url()
    hostname = urlsplit(page_url).hostname or ""
    ref = select_login(store.list_logins(hostname), page_url)
    value = store.read(ref, field)
    if not value:
        raise NoMatchError(f"{ref.name!r} has no {field.label}")
    browser.fill(selector, value, hostname, submit)
    submitted = f", then clicked {submit}" if submit else ""
    return f"filled {field.label} from {ref.name!r} into {selector} on {hostname}{submitted}"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--space", required=True, help="ego task space id or name")
    parser.add_argument("--page", required=True, help="page label in that space, e.g. p1")
    parser.add_argument("--selector", required=True, help="CSS selector of the input to fill")
    parser.add_argument("--field", required=True, type=parse_field, help="username | password | totp | custom:<name>")
    parser.add_argument(
        "--submit",
        default="",
        help="selector to click right after filling, in the same browser call; use it for a TOTP so it cannot expire in between",
    )
    args = parser.parse_args(argv)
    try:
        print(fill_credential(args.space, args.page, args.selector, args.field, args.submit))
    except CredentialFillError as error:
        print(f"credential-fill: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
