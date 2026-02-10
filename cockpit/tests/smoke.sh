#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd -P)"
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

require_match() {
  local text="$1"
  local pattern="$2"
  local label="$3"
  if printf '%s' "$text" | grep -qE "$pattern"; then
    pass "$label"
  else
    fail "$label (pattern not found: $pattern)"
  fi
}

prepare_tmp_repo() {
  local tmp
  tmp="$(mktemp -d)"
  cp -a "$REPO_ROOT/." "$tmp/repo"
  printf '%s\n' "$tmp/repo"
}

test_missing_py_venv_errors() {
  local tmp_repo out
  tmp_repo="$(prepare_tmp_repo)"
  rm -f "$tmp_repo/py_venv.sh"

  set +e
  out="$(bash "$tmp_repo/axiom.sh" --dry-run --skip-preflight 2>&1)"
  local rc=$?
  set -e

  [ "$rc" -ne 0 ] || fail "axiom.sh should fail when py_venv.sh is missing"
  require_match "$out" 'py_venv\.sh not found' "clear error when py_venv.sh missing"
}

test_venv_happens_before_preflight_output() {
  local tmp_repo out init_line preflight_line
  tmp_repo="$(prepare_tmp_repo)"

  set +e
  out="$(bash "$tmp_repo/axiom.sh" --dry-run 2>&1)"
  local rc=$?
  set -e

  [ "$rc" -eq 0 ] || fail "axiom.sh --dry-run should succeed in smoke run"

  init_line="$(printf '%s\n' "$out" | nl -ba | awk '/Initializing Python virtual environment/ {print $1; exit}')"
  preflight_line="$(printf '%s\n' "$out" | nl -ba | awk '/Running pre-flight safety checks/ {print $1; exit}')"

  [ -n "$init_line" ] || fail "did not find venv init output"
  [ -n "$preflight_line" ] || fail "did not find preflight output"
  [ "$init_line" -lt "$preflight_line" ] || fail "venv init must appear before preflight"
  pass "venv initialization occurs before preflight"
}

test_manifest_parsing() {
  local tmp_repo out
  tmp_repo="$(prepare_tmp_repo)"

  cat > "$tmp_repo/cockpit/install/MANIFEST" <<'MANIFEST'
# comment

  cockpit/bin/cockpit.sh

missing/stage.sh
cockpit/bin/blux10k.sh
MANIFEST

  set +e
  out="$(bash "$tmp_repo/axiom.sh" --dry-run --skip-preflight 2>&1)"
  local rc=$?
  set -e

  [ "$rc" -eq 0 ] || fail "axiom.sh --dry-run with manifest should succeed"
  require_match "$out" 'Loading install manifest' "manifest load message emitted"
  require_match "$out" 'Manifest stage missing, skipping: missing/stage\.sh' "missing manifest stage is warned/skipped"
  require_match "$out" 'RUN: cockpit/bin/cockpit\.sh' "first manifest stage run"
  require_match "$out" 'RUN: cockpit/bin/blux10k\.sh' "second manifest stage run"
}

main() {
  test_missing_py_venv_errors
  test_venv_happens_before_preflight_output
  test_manifest_parsing
  pass "all smoke checks completed"
}

main "$@"
