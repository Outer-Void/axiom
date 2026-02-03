![JADIS' Arsenal Locker](./assets/banner.png)

# locker

> A small “space-age” Bash toolbox: portable scripts for repo auditing, environment bootstrapping, drift checks, packaging, and architecture logs.

## Tools

- **orbitscan.sh** — Repo overview snapshot: git status/branch, top size offenders, common env/cache markers.
- **voidveil.sh** — Idempotently appends standard ignore rules to `.gitignore`.
- **nebula_boot.sh** — Creates/refreshes Python `.venv`, upgrades pip, installs `requirements.txt` if present.
- **chronos_probe.sh** — Environment fingerprint (OS/arch/shell/python/git/package manager) for Termux/proot/native parity.
- **riftfreeze.sh** — Dependency drift detector: write `baseline.txt` and diff against `current.txt`.
- **license_lens.sh** — Generates a dependency license report using `pip-licenses` (installs it if missing).
- **starmap.sh** — Prints a filtered repo tree (uses `tree`, falls back to `find`).
- **gravgrep.sh** — Fast recursive search for imports/refs (prefers `rg`, falls back to `grep`).
- **warpdrive.sh** — Universal task runner wrapper: `test`/`lint`/`run`, auto-uses local `.venv` when present.
- **artifact_compress.sh** — Builds a clean zip artifact excluding common caches/env/build outputs.
- **pulsecheck.sh** — Quick system resource snapshot (CPU/memory/disk).
- **admlog.sh** — Creates an ADR-lite decision log entry under `docs/decisions/`.

## Notes

- Scripts are intentionally dependency-light.
- Where available, `rg` and `tree` improve output but are optional.
