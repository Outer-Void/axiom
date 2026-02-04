#!/usr/bin/env bash
set -Eeuo pipefail

# axiom.sh — Full systems installer (root orchestrator)
# Builds the entire AXIOM environment in staged order.

############################################
# Helpers
############################################

die() { echo "AXIOM: ERROR: $*" >&2; exit 1; }
log() { echo "AXIOM: $*"; }

############################################
# Resolve repo root
############################################

resolve_self() {
  local src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

REPO_ROOT="$(resolve_self)"
cd "$REPO_ROOT" || die "Failed to cd to repo root: $REPO_ROOT"

############################################
# Python virtual environment (root)
############################################

PY_VENV="$REPO_ROOT/py_venv.sh"

if [[ -f "$PY_VENV" ]]; then
  log "Initializing Python virtual environment"
  # MUST be sourced
  # shellcheck source=/dev/null
  . "$PY_VENV"
else
  die "py_venv.sh not found at repo root"
fi

export AXIOM_VENV_ACTIVE=1

############################################
# Config
############################################

DEFAULT_MANIFEST="cockpit/install/MANIFEST"
MANIFEST="${AXIOM_MANIFEST:-$DEFAULT_MANIFEST}"

DRY_RUN="${AXIOM_DRY_RUN:-0}"
NONINTERACTIVE="${AXIOM_NONINTERACTIVE:-0}"

############################################
# CLI args
############################################

usage() {
  cat <<'USAGE'
Usage: ./axiom.sh [options]

Options:
  --manifest <path>     Use a custom manifest file
  --dry-run             Print actions without executing
  --noninteractive      Disable prompts for child scripts
  -h, --help            Show help

Env vars:
  AXIOM_MANIFEST=<path>
  AXIOM_DRY_RUN=1
  AXIOM_NONINTERACTIVE=1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      shift
      [[ $# -gt 0 ]] || die "--manifest requires a path"
      MANIFEST="$1"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --noninteractive)
      NONINTERACTIVE="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

############################################
# Preflight
############################################

log "Repo root : $REPO_ROOT"
log "Manifest  : $MANIFEST"

[[ -f "$MANIFEST" ]] || die "Manifest not found: $MANIFEST"

if [[ "$NONINTERACTIVE" == "1" ]]; then
  export AXIOM_NONINTERACTIVE=1
fi

############################################
# Execute staged installers
############################################

run_stage() {
  local rel="$1"
  local path="$REPO_ROOT/$rel"

  [[ -z "$rel" || "$rel" =~ ^# ]] && return 0
  [[ -f "$path" ]] || die "Missing installer: $rel"
  [[ -x "$path" ]] || die "Installer not executable: $rel"

  log "==> RUN: $rel"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "    (dry-run)"
    return 0
  fi

  "$path"
  log "<== OK:  $rel"
}

log "Starting AXIOM full install sequence"

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  run_stage "$line"
done < "$MANIFEST"

log "AXIOM installation complete"
