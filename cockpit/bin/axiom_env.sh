#!/usr/bin/env bash
# AXIOM Stage 3: local shell overlay installer.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
COCKPIT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd -P "${COCKPIT_DIR}/.." >/dev/null 2>&1 && pwd -P)"

# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/constants.sh"
# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/log.sh"
# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/platform.sh"
# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/runs.sh"

AXIOM_TOOLS_DIR="${HOME}/tools/scripts/axiom"
AXIOM_CONFIG_HOME="${HOME}/.config/axiom"
AXIOM_AX_SOURCE="${COCKPIT_DIR}/bin/ax"
AXIOM_AX_TARGET="${AXIOM_TOOLS_DIR}/ax"
AXIOM_ZSHRC_LOCAL="${HOME}/.zshrc.local"
AXIOM_BLOCK_TEMPLATE="${COCKPIT_DIR}/config/zshrc_axiom.block"
AXIOM_MARKER_START="### >>> AXIOM OVERLAY >>>"
AXIOM_MARKER_END="### <<< AXIOM OVERLAY <<<"

RUN_DIR=""
RUN_STARTED_AT=""

log_info() {
  axiom_log_info "$*"
  if [ -n "${RUN_DIR:-}" ]; then
    axiom_runs_write_output "$RUN_DIR" "[info] $*"
  fi
}

log_warn() {
  axiom_log_warn "$*"
  if [ -n "${RUN_DIR:-}" ]; then
    axiom_runs_write_output "$RUN_DIR" "[warn] $*"
  fi
}

log_error() {
  axiom_log_error "$*"
  if [ -n "${RUN_DIR:-}" ]; then
    axiom_runs_write_output "$RUN_DIR" "[error] $*"
  fi
}

render_overlay_block() {
  local escaped_root
  escaped_root="$(printf '%s' "$REPO_ROOT" | sed 's/[\\/&]/\\\\&/g')"
  sed "s|__AXIOM_REPO_ROOT__|${escaped_root}|g" "$AXIOM_BLOCK_TEMPLATE"
}

upsert_overlay_block() {
  local rendered_block temp_file
  rendered_block="$(render_overlay_block)"
  temp_file="$(mktemp)"

  if [ -f "$AXIOM_ZSHRC_LOCAL" ]; then
    awk -v start="$AXIOM_MARKER_START" -v end="$AXIOM_MARKER_END" '
      $0 == start { skip=1; next }
      $0 == end { skip=0; next }
      skip != 1 { print }
    ' "$AXIOM_ZSHRC_LOCAL" >"$temp_file"
  fi

  {
    cat "$temp_file"
    if [ -s "$temp_file" ]; then
      printf '\n'
    fi
    printf '%s\n' "$rendered_block"
  } >"${AXIOM_ZSHRC_LOCAL}"

  rm -f "$temp_file"
}

install_ax_command() {
  mkdir -p "$AXIOM_TOOLS_DIR"
  cp "$AXIOM_AX_SOURCE" "$AXIOM_AX_TARGET"
  chmod 755 "$AXIOM_AX_TARGET"
}

main() {
  RUN_STARTED_AT="$(date -Iseconds)"
  RUN_DIR="$(axiom_runs_create_dir "install" "axiom_env")"

  log_info "Installing AXIOM shell overlay"

  mkdir -p "$AXIOM_CONFIG_HOME"
  mkdir -p "$(dirname "$AXIOM_ZSHRC_LOCAL")"

  if [ ! -f "$AXIOM_ZSHRC_LOCAL" ]; then
    : >"$AXIOM_ZSHRC_LOCAL"
    chmod 644 "$AXIOM_ZSHRC_LOCAL" 2>/dev/null || true
    log_info "Created $AXIOM_ZSHRC_LOCAL"
  fi

  if [ ! -f "$AXIOM_BLOCK_TEMPLATE" ]; then
    log_error "Missing AXIOM overlay template: $AXIOM_BLOCK_TEMPLATE"
    axiom_runs_write_metadata "$RUN_DIR" "install" "axiom_env" "$0" "1" "$RUN_STARTED_AT" "$(date -Iseconds)" "$(pwd -P)"
    exit 1
  fi

  if [ ! -f "$AXIOM_AX_SOURCE" ]; then
    log_error "Missing AXIOM command source: $AXIOM_AX_SOURCE"
    axiom_runs_write_metadata "$RUN_DIR" "install" "axiom_env" "$0" "1" "$RUN_STARTED_AT" "$(date -Iseconds)" "$(pwd -P)"
    exit 1
  fi

  upsert_overlay_block
  install_ax_command

  log_info "AXIOM overlay updated in $AXIOM_ZSHRC_LOCAL"
  log_info "AXIOM command installed at $AXIOM_AX_TARGET"

  axiom_runs_write_metadata "$RUN_DIR" "install" "axiom_env" "$0" "0" "$RUN_STARTED_AT" "$(date -Iseconds)" "$(pwd -P)"
}

main "$@"
