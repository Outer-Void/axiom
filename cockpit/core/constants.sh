#!/usr/bin/env bash
set -euo pipefail

# Stable identity constants.
AXIOM_NAME="AXIOM"
AXIOM_DEV_HANDLE="Justadudeinspace (JADIS)"
AXIOM_EMAIL="theoutervoid@outlook.com"
AXIOM_GH_URL="https://github.com/Justadudeinspace"
AXIOM_REPO_URL="https://github.com/Justadudeinspace/axiom"

# Return the absolute directory of the calling script.
axiom_script_dir() {
  local source
  source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd -P
}

# Resolve to <repo>/cockpit based on this file's location.
axiom_cockpit_dir() {
  cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P
}

# Resolve to the repository root (parent of cockpit).
axiom_repo_root() {
  cd -P "$(axiom_cockpit_dir)/.." >/dev/null 2>&1 && pwd -P
}

# Resolve to <repo>/cockpit/config.
axiom_config_dir() {
  printf '%s\n' "$(axiom_cockpit_dir)/config"
}

# Resolve to <repo>/cockpit/runs.
axiom_runs_dir() {
  printf '%s\n' "$(axiom_cockpit_dir)/runs"
}

# Resolve to <repo>/locker.
axiom_locker_dir() {
  printf '%s\n' "$(axiom_repo_root)/locker"
}
