import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "credential_fill.py"
SPEC = importlib.util.spec_from_file_location("credential_fill", SCRIPT)
cf = importlib.util.module_from_spec(SPEC)
sys.modules["credential_fill"] = cf
SPEC.loader.exec_module(cf)

CAS = cf.LoginRef("cas", "cas.intranet", ("https://cas.example.com/login_en.html?service=x",))
BOT = cf.LoginRef("bot", "bot", ("https://cas.example.com/sys_login.html",))
ITOKEN = cf.LoginRef(
    "itoken",
    "itoken",
    ("https://captain.example.com/webconsole?env=prod", "https://cas.example.com/identify.html"),
)

SECRET = "hunter2-very-secret"
TOTP = "424242"


class SelectLoginTest(unittest.TestCase):
    def test_single_hostname_match_wins(self) -> None:
        picked = cf.select_login([CAS, BOT, ITOKEN], "https://captain.example.com/webconsole?env=fat&hostname=x")
        self.assertEqual(picked, ITOKEN)

    def test_path_breaks_a_hostname_tie(self) -> None:
        picked = cf.select_login([CAS, BOT, ITOKEN], "https://cas.example.com/identify.html")
        self.assertEqual(picked, ITOKEN)

    def test_no_hostname_match_refuses(self) -> None:
        with self.assertRaisesRegex(cf.NoMatchError, "evil.example.org"):
            cf.select_login([CAS, BOT, ITOKEN], "https://evil.example.org/login")

    def test_tie_left_after_path_refuses_and_names_candidates(self) -> None:
        twin = cf.LoginRef("twin", "cas-twin", CAS.uris)
        with self.assertRaisesRegex(cf.AmbiguousMatchError, "cas-twin, cas.intranet"):
            cf.select_login([CAS, twin], "https://cas.example.com/login_en.html")


class ParseFieldTest(unittest.TestCase):
    def test_custom_field_keeps_its_name(self) -> None:
        self.assertEqual(cf.parse_field("custom:sysAccount").label, "custom:sysAccount")

    def test_unknown_field_is_rejected(self) -> None:
        with self.assertRaises(Exception):
            cf.parse_field("passkey")


def write_stub(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text(f"#!{sys.executable}\n" + textwrap.dedent(body))
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


class EndToEndTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.page_url = self.tmp / "page_url"
        self.ego_stdin = self.tmp / "ego_stdin"
        self.page_url.write_text("https://captain.example.com/webconsole?env=fat")
        items = [
            {"id": "itoken", "name": "itoken", "login": {"uris": [{"uri": u} for u in ITOKEN.uris], "password": SECRET}},
            {"id": "cas", "name": "cas.intranet", "login": {"uris": [{"uri": u} for u in CAS.uris], "password": SECRET}},
        ]
        write_stub(
            self.tmp,
            "bw",
            f"""
            import json, sys
            args = sys.argv[1:]
            if args[:2] == ["list", "items"]:
                print(json.dumps({items!r}))
            elif args[:2] == ["get", "totp"] and args[2] == "itoken":
                print({TOTP!r})
            elif args[:2] == ["get", "password"]:
                import os
                moved = os.environ.get("MOVE_PAGE_TO")
                if moved:
                    open({str(self.page_url)!r}, "w").write(moved)
                print({SECRET!r})
            else:
                sys.exit(1)
            """,
        )
        write_stub(
            self.tmp,
            "ego-browser",
            f"""
            import sys
            script = sys.stdin.read()
            open({str(self.ego_stdin)!r}, "a").write(script + "\\n---\\n")
            url = open({str(self.page_url)!r}).read()
            # Like the real ego-browser off a terminal, console.log goes to stderr.
            if ".fill(" not in script:
                print("CF_URL=" + url, file=sys.stderr)
            elif '"' + __import__("urllib.parse").parse.urlsplit(url).hostname + '"' in script:
                print("CF_FILLED", file=sys.stderr)
            else:
                print("Error: page moved", file=sys.stderr)
                sys.exit(1)
            """,
        )

    def run_cli(self, *args: str, move_page_to: str = "") -> subprocess.CompletedProcess[str]:
        env = {
            **os.environ,
            "PATH": f"{self.tmp}{os.pathsep}{os.environ['PATH']}",
            "BW_SESSION": "test",
            "MOVE_PAGE_TO": move_page_to,
        }
        env.pop("OP_SERVICE_ACCOUNT_TOKEN", None)
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--space", "11", "--page", "p2", *args],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

    def test_fills_totp_and_never_prints_it(self) -> None:
        result = self.run_cli("--selector", "input[name=otpcode]", "--field", "totp")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("filled totp from 'itoken' into input[name=otpcode] on captain.example.com", result.stdout)
        self.assertNotIn(TOTP, result.stdout + result.stderr)
        sent = self.ego_stdin.read_text()
        self.assertNotIn(TOTP, sent, "the value must reach ego base64-encoded, not in clear")

    def test_submit_clicks_in_the_same_browser_call(self) -> None:
        result = self.run_cli("--selector", "input[name=otpcode]", "--field", "totp", "--submit", "#verify")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("then clicked #verify", result.stdout)
        fill_call = self.ego_stdin.read_text().split("---")[-2]
        self.assertIn(".fill(", fill_call)
        self.assertIn('.click("#verify"', fill_call)

    def test_refuses_when_the_page_moves_after_selection(self) -> None:
        self.page_url.write_text("https://cas.example.com/login_en.html")
        result = self.run_cli("--selector", "#pw", "--field", "password", move_page_to="https://evil.example.org/x")
        self.assertEqual(result.returncode, 2)
        self.assertIn("could not fill #pw", result.stderr)
        self.assertNotIn(SECRET, result.stdout + result.stderr)

    def test_refuses_a_page_with_no_matching_login(self) -> None:
        self.page_url.write_text("https://evil.example.org/login")
        result = self.run_cli("--selector", "#pw", "--field", "password")
        self.assertEqual(result.returncode, 2)
        self.assertIn("no login has a URL on evil.example.org", result.stderr)
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assertNotIn(".fill(", self.ego_stdin.read_text())


if __name__ == "__main__":
    unittest.main()
