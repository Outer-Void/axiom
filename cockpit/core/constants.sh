#!/usr/bin/env bash

# Stable identity constants.
AXIOM_NAME="AXIOM"
AXIOM_DEV_HANDLE="Justadudeinspace (JADIS)"
AXIOM_EMAIL="theoutervoid@outlook.com"
AXIOM_GH_URL="https://github.com/Justadudeinspace"
AXIOM_REPO_URL="https://github.com/Justadudeinspace/axiom"
BLUXGPT_READY="${BLUXGPT_READY:-0}"
BLUXGPT_VERSION="${BLUXGPT_VERSION:-}"

# Return the absolute directory of the calling script.
# FIXED: Added basic error handling
axiom_script_dir() {
  local source
  source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  if [ -z "$source" ]; then
    echo "."  # Safe fallback
    return 1
  fi
  (cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd -P) || {
    echo "."  # Safe fallback on error
    return 1
  }
}

# Resolve to <repo>/cockpit based on this file's location.
axiom_cockpit_dir() {
  (cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P) || {
    echo "."  # Safe fallback
    return 1
  }
}

# Resolve to the repository root (parent of cockpit).
axiom_repo_root() {
  local cockpit_dir
  cockpit_dir="$(axiom_cockpit_dir)"
  (cd -P "$cockpit_dir/.." >/dev/null 2>&1 && pwd -P) || {
    echo "."  # Safe fallback
    return 1
  }
}

# Resolve to <repo>/cockpit/config.
axiom_config_dir() {
  local cockpit_dir
  cockpit_dir="$(axiom_cockpit_dir)"
  printf '%s\n' "$cockpit_dir/config"
}

# Resolve to <repo>/cockpit/runs.
axiom_runs_dir() {
  local cockpit_dir
  cockpit_dir="$(axiom_cockpit_dir)"
  printf '%s\n' "$cockpit_dir/runs"
}

# Resolve to <repo>/locker.
axiom_locker_dir() {
  local repo_root
  repo_root="$(axiom_repo_root)"
  printf '%s\n' "$repo_root/locker"
}
