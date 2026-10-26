![AXIOM Banner](assets/axiom_banner.png)

> SENTINEL / NIGHT OPS — Debian-first dev cockpit

AXIOM is my personal terminal operating environment and autonomous systems vessel.

This repository is built around one core doctrine:

> Debian is home. Everything should feel like Debian — even when it isn’t.

AXIOM converges Termux, WSL2, Linux distros, and macOS into a predictable, professional developer environment, with a disciplined operational cockpit layered on top.

---

## `ax`: the Outer Void control plane

`ax` routes; it does not reimplement. Each command execs the real engine with your arguments unchanged. When
an engine is missing, `ax` says which one and exits 69. It never does the work itself.

| Command | Engine |
|---|---|
| `ax env` | blux10k (environment and toolchain authority) |
| `ax tools` | GOD (`god commands`) |
| `ax ask` | BLUX (`blux ask`) |
| `ax agent` | BLUX Runtime (`blux agent`) |
| `ax reason` | CogA (`coga`) |
| `ax build` | cA (`ca`) |
| `ax create` | LRC (`lrc`) |
| `ax audit` | DAT (`dat`) |
| `ax projects` | GOD (`god index`) |
| `ax inspect` | BLUX System (`blux-system`) |
| `ax capabilities` | GOD (`god capabilities`), else the BLUX registry |
| `ax devices` | VoidForge (`voidforge` integration client) |

- **Doctor.** `ax doctor` shows which engines resolve, plus blux10k's environment verdict.
- **Routes.** `ax routes` prints the routing table.
- **Overrides.** `AX_BIN_<ENGINE>` points `ax` at a specific engine executable.
- **Devices.** `ax devices` routes to the VoidForge client (Stage 22). VoidForge stays the authority: it
  must be running with local integrations enabled, and every write is confirmed on the VoidForge device.
  Without VoidForge, `ax devices` exits 69.
- **Source.** The router is `cockpit/ax/router.py`, tested in `tests/test_ax_router.py`.
- **Legacy check.** The previous AXIOM + blux10k + BluxGPT prerequisite check is `ax trifecta`.

## Repository structure (high level)

Each major directory contains its own `README.md` with detailed documentation.
This root README exists to explain the system as a whole and how the pieces fit together.

```
axiom/
├── cockpit/    environment bootstrap + operational cockpit
├── locker/     standalone tools (callable directly or via Overwatch)
├── armory/     reserved for heavier payloads / future modules
├── assets/     visuals and branding
├── py_venv.sh  python virtual environment helper
```

---

## Install & Launch 

```
# Install AXIOM
git clone https://github.com/Justadudeinspace/axiom.git
cd axiom
./axiom.sh

# Launch AXIOM
./launch.sh
```

`./axiom.sh` is a live staged installer and may pause during legitimate long-running provisioning (sudo, apt, curl/bootstrap, locale generation). Keep the terminal attached and read live logs.

### Installer behavior (important)

`./axiom.sh` runs a strict staged sequence:

1. `cockpit/bin/cockpit.sh`
2. `cockpit/bin/blux10k.sh`
3. `cockpit/bin/axiom_env.sh`

Each stage runs with a timeout and live output. AXIOM does not hide installer output and does not silently auto-answer prompts.
Stage end states are reported distinctly (success, timeout, non-zero exit, or stage file/exec problems) so failures are not flattened into misleading "done" output.

If a child installer cannot be proven safe for noninteractive execution, AXIOM fails closed with a manual command block so you can run it directly with visible prompts.

Stage 2 (`cockpit/bin/blux10k.sh`) depends on proving a safe noninteractive blux10k installer path. If that cannot be proven, AXIOM intentionally stops with a manual command block rather than attempting hidden interactive automation, and it will not report success for an incomplete stage.

---

## `cockpit/` — the command deck

The cockpit is the heart of AXIOM. It prepares, builds, and operates the developer environment.

### Key components:

`cockpit/bin/cockpit.sh`  
Baseline bootstrap. Establishes a Debian-like foundation.  
Supports native Debian/Linux, WSL2 (Debian), and Termux via proot-distro Debian.

`cockpit/bin/blux10k.sh`  
blux10k prerequisite gate: verifies or installs the blux10k foundation required by AXIOM.
It only executes known noninteractive installer paths. If that safety check is not met, it exits with an explicit manual fallback command.

`cockpit/bin/overwatch.sh`  
A full-screen TUI cockpit for operating AXIOM:
observe past runs, operate locker tools, inspect signals, navigate the filesystem, and perform cleanup operations.
When BluxGPT is available (`BLUXGPT_READY=1` with a valid `BLUXGPT_REPO_ROOT`), Overwatch prefers it for AI actions and falls back to `gpt-4o-mini.sh` when BluxGPT is unavailable.

`cockpit/bin/gpt-4o-mini.sh`  
Optional AI sidecar installer and connectivity tester.
Used strictly for review, diagnostics, and cleanup assistance — never for command execution.

### Supporting directories:

`cockpit/config/`  
Configuration templates and local configuration files.
Includes .zshrc and .env.example (copy to .env locally; never commit secrets).

`cockpit/runs/`  
Flight-recorder style execution artifacts generated by Overwatch and cockpit workflows.

---

### `locker/` — the toolkit vault

The locker contains curated standalone scripts for analysis, scanning, compression, inspection, and repository operations.

Locker tools are designed to be:
- safe to run directly  
- discoverable and operable through Overwatch  
- logged automatically when executed via the cockpit  

Each tool documents its intent and behavior in `locker/README.md`.

---

### `armory/` — expansion bay

The armory is reserved for heavier payloads and future modules:
larger systems, experimental components, or anything that does not belong in the cockpit or locker.

This space is intentionally empty for now.

---

## Debian-first doctrine

AXIOM works best on:

- Debian / Debian-based Linux  
- WSL2 with Debian  
- Termux with proot-distro Debian  

macOS and Windows-native are supported where practical, but the gold path is Debian.

If you want the intended experience:
Use Debian. Everything else is compatibility mode.

---

## Theme & philosophy

OVERWATCH: SENTINEL / NIGHT OPS

- dark armored interfaces  
- ember signal accents  
- muted steel information tones  
- no noise, no gimmicks  
- confirm before execution  
- log everything  
- never leak secrets  
- AI is advisory only  

This is a cockpit — not a toy.

---

## Getting started (high level)

1. Clone the repository and enter it.

2. Optional: create a Python virtual environment for Overwatch development and testing.

3. Bootstrap the environment with `cockpit.sh`.

4. Launch the cockpit via `overwatch.sh`.

5. Run `blux10k.sh` to verify/install blux10k and `axiom_env.sh` to maintain the AXIOM `~/.zshrc.local` overlay.

Refer to each directory’s `README.md` for detailed usage.

---

## Security & secrets

Secrets belong in `cockpit/config/.env` (local only).
`.env.example` is a template — not a secret store.

- API keys are never printed.  
- Overwatch never auto-executes AI output.  
- All executions are logged.

---

# License

**Outer-Void Proprietary License** (proprietary). Copyright (c) 2026 Outer-Void / Justadudeinspace (JADIS). All rights reserved. See [LICENSE](LICENSE).

Copies and releases obtained before 2026-10-25 remain available under the Apache License 2.0 they were
published with; every change and release from that date on is proprietary.

Contact: outervoid.blux@gmail.com (main) · theoutervoid@outlook.com (fallback)

---

> JADIS — Just A Dude In Space

Built to be used. Built to survive. Built for Debian.
