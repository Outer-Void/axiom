# cockpit/core

`cockpit/core` provides the shared, side-effect free shell utilities used by Axiom.
These helpers are designed for Bash 3.x+ (macOS default) and Termux-friendly usage.

## What each file provides

- `constants.sh`: Stable identity constants and path resolution helpers.
- `shell.sh`: Command checks, TTY helpers, safe mkdir, time, and mktemp compatibility.
- `log.sh`: Standardized logging and error helpers.
- `platform.sh`: Platform detection and summaries.
- `env.sh`: `.env` parsing, environment helpers, and template creation.
- `runs.sh`: Flight recorder helpers (the only core module that creates files/dirs).

## Core is side-effect free

All modules are side-effect free by default (except `runs.sh`, which intentionally writes
run artifacts).

## Recommended sourcing order

1. `constants.sh`
2. `shell.sh`
3. `log.sh`
4. `platform.sh`
5. `env.sh`
6. `runs.sh`

## Quick example

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${BASH_SOURCE[0]%/*}/core/constants.sh"
source "$(axiom_cockpit_dir)/core/shell.sh"
source "$(axiom_cockpit_dir)/core/log.sh"
source "$(axiom_cockpit_dir)/core/platform.sh"

platform="$(axiom_detect_platform)"
axiom_log_info "Platform: $platform"
```
