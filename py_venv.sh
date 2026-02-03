#!/usr/bin/env bash
set -euo pipefail

VENV_DIR=".venv"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[py-venv] python3 not found in PATH" >&2
  exit 1
fi

if [ ! -d "${VENV_DIR}" ]; then
  echo "[py-venv] Creating virtual environment (${VENV_DIR})"
  python3 -m venv "${VENV_DIR}"
else
  echo "[py-venv] Virtual environment already exists (${VENV_DIR})"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

echo "[py-venv] Activated virtual environment"
echo "[py-venv] Python: $(python --version)"
echo "[py-venv] Pip: $(pip --version)"
