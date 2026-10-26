"""`ax`: the thin Outer Void control plane (Stage 18). AX routes; it does not reimplement.

Every command resolves one engine and execs it with the user's arguments unchanged. AX holds no
engine logic, imports no engine package and post-processes no output.

    ax doctor          AX's own check: which engines resolve (plus blux10k's environment verdict)
    ax routes          print the routing table
    ax env ...         -> blux10k            (environment / toolchain authority)
    ax tools ...       -> god commands       (tools discovered on PATH)
    ax ask ...         -> blux ask           (direct intelligence)
    ax agent ...       -> blux agent         (BLUX Runtime agent loop)
    ax reason ...      -> coga               (CogA)
    ax build ...       -> ca                 (cA)
    ax create ...      -> lrc                (LRC)
    ax audit ...       -> dat                (DAT)
    ax projects ...    -> god index          (GOD project discovery)
    ax inspect ...     -> blux-system        (BLUX System)
    ax capabilities .. -> god capabilities   (GOD), else blux capabilities (BLUX registry)

There is deliberately no `ax devices`. An engine is found on PATH, or through AX_BIN_<ENGINE>
(for example AX_BIN_BLUX10K=/path/to/blux10k). When it is missing, AX says which engine and exits 69
(EX_UNAVAILABLE). It never falls back to doing the work itself.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass

EX_UNAVAILABLE = 69


@dataclass(frozen=True)
class Route:
    command: str
    engine: str
    executable: str
    prefix: tuple[str, ...] = ()
    default: tuple[str, ...] = ()
    fallback: tuple[str, tuple[str, ...]] | None = None  # (executable, prefix) when the primary is missing
    summary: str = ""


ROUTES: dict[str, Route] = {
    r.command: r
    for r in (
        Route("env", "blux10k", "blux10k", default=("report",), summary="environment and toolchain authority"),
        Route("tools", "GOD", "god", prefix=("commands",), summary="tools discovered on PATH"),
        Route("ask", "BLUX", "blux", prefix=("ask",), summary="direct intelligence"),
        Route("agent", "BLUX Runtime", "blux", prefix=("agent",), summary="agent loop"),
        Route("reason", "CogA", "coga", default=("--help",), summary="structured reasoning"),
        Route("build", "cA", "ca", default=("--help",), summary="construction and repair"),
        Route("create", "LRC", "lrc", default=("--help",), summary="repository creation"),
        Route("audit", "DAT", "dat", default=("--help",), summary="quality, security and release audits"),
        Route("projects", "GOD", "god", prefix=("index",), summary="project discovery"),
        Route("inspect", "BLUX System", "blux-system", default=("--help",), summary="execution truth: receipts and graphs"),
        Route("capabilities", "GOD", "god", prefix=("capabilities",), fallback=("blux", ("capabilities",)),
              summary="capability discovery (GOD, else the BLUX registry)"),
    )
}
VERSION_ARGS = {"blux10k": ["--version"], "god": ["version"], "blux": ["version"], "coga": ["--version"], "ca": ["--version"],
                "lrc": ["version"], "dat": ["--version"], "blux-system": ["version"]}


def resolve(executable: str) -> str | None:
    override = os.environ.get("AX_BIN_" + executable.upper().replace("-", "_"))
    if override:
        return override if os.access(override, os.X_OK) else None
    return shutil.which(executable)


def target(route: Route) -> tuple[list[str], str] | None:
    """The argv AX will exec for this route (without user args), or None when no engine resolves."""
    exe = resolve(route.executable)
    if exe:
        return [exe, *route.prefix], route.engine
    if route.fallback:
        alt = resolve(route.fallback[0])
        if alt:
            return [alt, *route.fallback[1]], "BLUX registry"
    return None


def doctor(as_json: bool) -> int:
    rows = []
    for name, route in ROUTES.items():
        found = target(route)
        version = None
        if found:
            exe = found[0][0]
            base = os.path.basename(exe)
            try:
                proc = subprocess.run([exe, *VERSION_ARGS.get(base, ["--version"])], capture_output=True, text=True, timeout=30, check=False)  # noqa: S603
                version = (proc.stdout or proc.stderr).strip().splitlines()[0][:120] if (proc.stdout or proc.stderr).strip() else None
            except (OSError, subprocess.TimeoutExpired):
                version = None
        rows.append({"command": f"ax {name}", "engine": route.engine, "executable": found[0][0] if found else None,
                     "via": found[1] if found else None, "available": bool(found), "version": version})
    env_verdict = None
    b10k = resolve("blux10k")
    if b10k:
        proc = subprocess.run([b10k, "doctor", "--json"], capture_output=True, text=True, timeout=300, check=False)  # noqa: S603
        try:
            env_verdict = {"healthy": json.loads(proc.stdout)["healthy"], "exit_code": proc.returncode}
        except (ValueError, KeyError):
            env_verdict = {"healthy": None, "exit_code": proc.returncode}
    missing = [r["command"] for r in rows if not r["available"]]
    doc = {"contract": "ax.doctor", "routes": rows, "environment": env_verdict, "missing": missing, "ok": not missing}
    if as_json:
        sys.stdout.write(json.dumps(doc, indent=1) + "\n")
    else:
        for r in rows:
            mark = "ok  " if r["available"] else "MISSING"
            sys.stdout.write(f"[{mark}] {r['command']:16} -> {r['engine']:12} {r['executable'] or '(not installed)'}"
                             f"{'  ' + r['version'] if r['version'] else ''}\n")
        if env_verdict is not None:
            sys.stdout.write(f"environment (blux10k doctor): {'healthy' if env_verdict['healthy'] else 'problems; run ax env doctor'}\n")
    return 0 if not missing else 1


def usage() -> str:
    lines = ["usage: ax COMMAND [ARGS...]", "", "  doctor           which engines resolve", "  routes           the routing table"]
    lines += [f"  {n:16} -> {r.engine}: {r.summary}" for n, r in ROUTES.items()]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in ("-h", "--help", "help"):
        sys.stdout.write(usage())
        return 0 if args else 2
    cmd, rest = args[0], args[1:]
    if cmd == "doctor":
        return doctor("--json" in rest)
    if cmd == "routes":
        sys.stdout.write(json.dumps({n: {"engine": r.engine, "argv": [r.executable, *r.prefix], "default": list(r.default),
                                         "fallback": [r.fallback[0], *r.fallback[1]] if r.fallback else None}
                                     for n, r in ROUTES.items()}, indent=1) + "\n")
        return 0
    route = ROUTES.get(cmd)
    if route is None:
        sys.stderr.write(f"ax: unknown command {cmd!r}\n{usage()}")
        return 2
    found = target(route)
    if found is None:
        sys.stderr.write(
            f"ax: `ax {cmd}` routes to {route.engine} (`{route.executable}`), which is not installed or not on PATH.\n"
            f"ax: install it, or point AX_BIN_{route.executable.upper().replace('-', '_')} at it. AX does not do this work itself.\n"
        )
        return EX_UNAVAILABLE
    argv_out = [*found[0], *(rest or list(route.default))]
    os.execv(argv_out[0], argv_out)  # noqa: S606 - the engine replaces AX; exit code and output are the engine's
    return 0  # pragma: no cover


if __name__ == "__main__":
    sys.exit(main())
