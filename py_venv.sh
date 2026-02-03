#!/bin/sh
# py_venv.sh — MUST be sourced: . ./py_venv.sh

VENV_DIR=".venv"

# Function to detect if script is being sourced
_is_sourced() {
  if [ -n "$ZSH_VERSION" ]; then
    case $ZSH_EVAL_CONTEXT in *:file:*) return 0;; esac
  elif [ -n "$KSH_VERSION" ]; then
    [ "$(cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")" != "$(cd -- "$(dirname -- "${.sh.file}")" && pwd -P)/$(basename -- "${.sh.file}")" ] && return 0
  elif [ -n "$BASH_VERSION" ]; then
    (return 0 2>/dev/null) && return 0 || return 1
  else
    # Universal fallback: 'return' only works when sourced
    (return 0 2>/dev/null) && return 0 || return 1
  fi
  return 1
}

# If not sourced, show helpful message and exit gracefully
if ! _is_sourced; then
  cat >&2 << 'EOF'
[py-venv] ERROR: This script must be SOURCED, not executed.

Correct usage:
  . ./py_venv.sh     # POSIX shells (sh, bash, dash, etc.)
  source ./py_venv.sh # bash, zsh, ksh

Why source?
  Virtual environment activation modifies the current shell's environment.
  These changes can't persist if the script runs in a subshell.

EOF
  # Safe termination: replace script process with no-op
  exec true
fi

# Idempotency check - skip if already active
_CURRENT_VENV="$(pwd)/$VENV_DIR"
if [ -n "$VIRTUAL_ENV" ] && [ "$VIRTUAL_ENV" = "$_CURRENT_VENV" ]; then
  echo "[py-venv] ✓ Virtual environment already active"
  echo "[py-venv]   Path: $VIRTUAL_ENV"
  return 0 2>/dev/null || exit 0
fi

# Check for Python
if ! command -v python3 >/dev/null 2>&1; then
  echo "[py-venv] ERROR: python3 not found in PATH" >&2
  return 1 2>/dev/null || exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
  echo "[py-venv] Creating virtual environment ($VENV_DIR)"
  if ! python3 -m venv "$VENV_DIR"; then
    echo "[py-venv] ERROR: Failed to create virtual environment" >&2
    return 1 2>/dev/null || exit 1
  fi
else
  echo "[py-venv] Found virtual environment ($VENV_DIR)"
fi

# Check if activation script exists
if [ ! -f "$VENV_DIR/bin/activate" ]; then
  echo "[py-venv] ERROR: Activation script not found: $VENV_DIR/bin/activate" >&2
  return 1 2>/dev/null || exit 1
fi

# Activate with optional debug output
if [ -n "$PY_VENV_DEBUG" ]; then
  echo "[py-venv] Debug mode: Showing activation output"
  . "$VENV_DIR/bin/activate"
else
  . "$VENV_DIR/bin/activate" 2>/dev/null
fi

# Verify activation worked
if [ -z "$VIRTUAL_ENV" ] || [ ! -d "$VIRTUAL_ENV" ]; then
  echo "[py-venv] ERROR: Virtual environment failed to activate" >&2
  echo "[py-venv]        VIRTUAL_ENV is not set or invalid" >&2
  return 1 2>/dev/null || exit 1
fi

# Show success message
echo "[py-venv] ✓ Virtual environment activated"
echo "[py-venv]   Python: $(python --version 2>/dev/null || echo 'not found')"
echo "[py-venv]   Pip: $(pip --version 2>/dev/null | cut -d' ' -f1-2 2>/dev/null || echo 'not found')"
echo "[py-venv]   Path: $VENV_DIR"
echo "[py-venv]   To deactivate, run: deactivate"
