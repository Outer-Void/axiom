"""AX router tests (stdlib unittest): every command execs its real engine; nothing is reimplemented.

Stub engines on a temporary PATH record the argv they receive, so the tests prove which engine runs and that
user arguments arrive unchanged. Missing engines fail explicitly with exit 69.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROUTER = ROOT / "cockpit" / "ax" / "router.py"
AX = ROOT / "cockpit" / "bin" / "ax-route"
ENGINES = ("blux10k", "god", "blux", "coga", "ca", "lrc", "dat", "blux-system")
EXPECTED = {
    "env": ("blux10k", []), "tools": ("god", ["commands"]), "ask": ("blux", ["ask"]), "agent": ("blux", ["agent"]),
    "reason": ("coga", []), "build": ("ca", []), "create": ("lrc", []), "audit": ("dat", []), "projects": ("god", ["index"]),
    "inspect": ("blux-system", []), "capabilities": ("god", ["capabilities"]),
}


class Stubs:
    def __init__(self, names: tuple[str, ...]) -> None:
        self.dir = Path(tempfile.mkdtemp(prefix="ax-stubs-"))
        self.log = self.dir / "calls.jsonl"
        for name in names:
            path = self.dir / name
            path.write_text(
                f"#!{sys.executable}\nimport json, sys\n"
                f"open({str(self.log)!r}, 'a').write(json.dumps({{'engine': {name!r}, 'argv': sys.argv[1:]}}) + '\\n')\n"
                "print('stub ' + ' '.join(sys.argv[1:]))\n"
                "sys.exit(7 if '--fail' in sys.argv else 0)\n"
            )
            path.chmod(0o755)

    def calls(self) -> list[dict[str, object]]:
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def env(self) -> dict[str, str]:
        base = {k: v for k, v in os.environ.items() if not k.startswith("AX_BIN_")}
        return {**base, "PATH": f"{self.dir}:/usr/bin:/bin"}


def ax(*args: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(AX), *args], capture_output=True, text=True, env=env, timeout=120, check=False)


class Routing(unittest.TestCase):
    def test_every_command_execs_its_engine_with_arguments_unchanged(self) -> None:
        stubs = Stubs(ENGINES)
        for cmd, (engine, prefix) in EXPECTED.items():
            proc = ax(cmd, "--flag", "two words", "--x=1", env=stubs.env())
            self.assertEqual(proc.returncode, 0, (cmd, proc.stderr))
            call = stubs.calls()[-1]
            self.assertEqual(call, {"engine": engine, "argv": [*prefix, "--flag", "two words", "--x=1"]}, cmd)

    def test_engine_exit_code_and_output_pass_through(self) -> None:
        stubs = Stubs(ENGINES)
        proc = ax("audit", "release", "--fail", env=stubs.env())
        self.assertEqual(proc.returncode, 7)
        self.assertEqual(proc.stdout, "stub release --fail\n")

    def test_defaults_when_no_arguments(self) -> None:
        stubs = Stubs(ENGINES)
        ax("env", env=stubs.env())
        ax("reason", env=stubs.env())
        self.assertEqual([c["argv"] for c in stubs.calls()], [["report"], ["--help"]])

    def test_missing_engine_fails_explicitly(self) -> None:
        stubs = Stubs(tuple(e for e in ENGINES if e != "coga"))
        proc = ax("reason", "plan", env=stubs.env())
        self.assertEqual(proc.returncode, 69)
        self.assertIn("routes to CogA (`coga`), which is not installed", proc.stderr)
        self.assertEqual(stubs.calls(), [])

    def test_capabilities_falls_back_to_the_blux_registry_only(self) -> None:
        stubs = Stubs(tuple(e for e in ENGINES if e != "god"))
        self.assertEqual(ax("capabilities", env=stubs.env()).returncode, 0)
        self.assertEqual(stubs.calls()[-1], {"engine": "blux", "argv": ["capabilities"]})
        self.assertEqual(ax("projects", env=stubs.env()).returncode, 69)  # no fallback: GOD owns projects

    def test_override_variables(self) -> None:
        stubs = Stubs(ENGINES)
        env = {**stubs.env(), "PATH": "/usr/bin:/bin", "AX_BIN_BLUX10K": str(stubs.dir / "blux10k")}
        self.assertEqual(ax("env", "detect", env=env).returncode, 0)
        self.assertEqual(stubs.calls()[-1]["argv"], ["detect"])

    def test_unknown_commands_and_no_devices(self) -> None:
        stubs = Stubs(ENGINES)
        self.assertEqual(ax("devices", env=stubs.env()).returncode, 2)
        self.assertEqual(ax(env=stubs.env()).returncode, 2)
        routes = json.loads(ax("routes", env=stubs.env()).stdout)
        self.assertEqual(sorted(routes), sorted(EXPECTED))

    def test_doctor_reports_availability(self) -> None:
        stubs = Stubs(tuple(e for e in ENGINES if e != "dat"))
        proc = ax("doctor", "--json", env=stubs.env())
        doc = json.loads(proc.stdout)
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(doc["missing"], ["ax audit"])
        self.assertTrue(all(r["available"] for r in doc["routes"] if r["command"] != "ax audit"))


class NoReimplementation(unittest.TestCase):
    def test_router_holds_no_engine_logic(self) -> None:
        source = ROUTER.read_text()
        imports = re.findall(r"^\s*(?:import|from)\s+([\w.]+)", source, re.M)
        self.assertEqual(sorted(set(imports)), ["__future__", "dataclasses", "json", "os", "shutil", "subprocess", "sys"])
        self.assertIn("os.execv(", source)  # the engine replaces AX; AX never post-processes engine output


if __name__ == "__main__":
    unittest.main()
