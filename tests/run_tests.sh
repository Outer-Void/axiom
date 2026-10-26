#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# AXIOM Test Suite Runner
# Tier: Testing Framework (Standalone)
# Description: Runs tests for AXIOM components
# Dependencies: bash, core libraries (for some tests)
# Usage: ./run_tests.sh [test_pattern] [options]
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
COCKPIT_DIR="$REPO_ROOT/cockpit"
CORE_DIR="$COCKPIT_DIR/core"
LOCKER_DIR="$REPO_ROOT/locker"
COCKPIT_BIN_DIR="$COCKPIT_DIR/bin"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Output formatting
_print_header() {
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "${BLUE}AXIOM Test Suite${NC}"
  echo -e "${BLUE}Running: $(date)${NC}"
  echo -e "${BLUE}================================================================================${NC}"
  echo ""
}

_print_footer() {
  echo ""
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "${BLUE}Test Results${NC}"
  echo -e "${BLUE}================================================================================${NC}"
  
  if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo -e "  Total: $TOTAL_TESTS, Passed: $PASSED_TESTS, Failed: $FAILED_TESTS, Skipped: $SKIPPED_TESTS"
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo -e "  Total: $TOTAL_TESTS, Passed: $PASSED_TESTS, Failed: $FAILED_TESTS, Skipped: $SKIPPED_TESTS"
  fi
}

_print_test_start() {
  local test_name="$1"
  echo -e "${BLUE}[TEST]${NC} $test_name"
}

_print_test_result() {
  local test_name="$1"
  local result="$2"
  local message="${3:-}"
  
  case "$result" in
    PASS)
      echo -e "  ${GREEN}✓ PASS${NC} $test_name"
      if [ -n "$message" ]; then
        echo -e "    $message"
      fi
      ;;
    FAIL)
      echo -e "  ${RED}✗ FAIL${NC} $test_name"
      if [ -n "$message" ]; then
        echo -e "    $message"
      fi
      ;;
    SKIP)
      echo -e "  ${YELLOW}↷ SKIP${NC} $test_name"
      if [ -n "$message" ]; then
        echo -e "    $message"
      fi
      ;;
  esac
  echo ""
}

# Test runner
run_test() {
  local test_name="$1"
  local test_func="$2"
  
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  _print_test_start "$test_name"
  
  # Run test in subshell to catch errors
  if (set +e; $test_func >/tmp/test_output_$$.log 2>&1); then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    _print_test_result "$test_name" "PASS"
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    local error_msg
    error_msg=$(tail -5 /tmp/test_output_$$.log 2>/dev/null || echo "Test failed")
    _print_test_result "$test_name" "FAIL" "$error_msg"
    
    # Show full output in verbose mode
    if [ "${VERBOSE:-0}" = "1" ]; then
      echo "  Test output:"
      cat /tmp/test_output_$$.log | sed 's/^/    /'
      echo ""
    fi
  fi
  
  rm -f /tmp/test_output_$$.log
}

skip_test() {
  local test_name="$1"
  local reason="$2"
  
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
  _print_test_start "$test_name"
  _print_test_result "$test_name" "SKIP" "$reason"
}

# =============================================================================
# CORE LIBRARY TESTS
# =============================================================================

test_constants() {
  # Load constants
  source "$CORE_DIR/constants.sh"
  
  # Test path resolution functions
  local script_dir
  script_dir="$(axiom_script_dir)"
  
  [ -n "$script_dir" ] && [ -d "$script_dir" ] || return 1
  
  local cockpit_dir
  cockpit_dir="$(axiom_cockpit_dir)"
  [ "$cockpit_dir" = "$COCKPIT_DIR" ] || return 1
  
  local repo_root
  repo_root="$(axiom_repo_root)"
  [ "$repo_root" = "$REPO_ROOT" ] || return 1
  
  # Test config dir
  local config_dir
  config_dir="$(axiom_config_dir)"
  [ "$config_dir" = "$COCKPIT_DIR/config" ] || return 1
  
  return 0
}

test_logging() {
  source "$CORE_DIR/log.sh"
  
  # Test that functions exist
  type axiom_log_info >/dev/null 2>&1 || return 1
  type axiom_log_warn >/dev/null 2>&1 || return 1
  type axiom_log_error >/dev/null 2>&1 || return 1
  type axiom_die >/dev/null 2>&1 || return 1
  
  # axiom_die must return non-zero (not exit) and print the message. Capture first, then check: piping a
  # deliberately failing command into grep under `set -o pipefail` was a false negative.
  local out rc
  out="$(axiom_die "Test error" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || return 1
  [[ "$out" == *"[axiom][error] Test error"* ]] || return 1
  
  return 0
}

test_platform() {
  source "$CORE_DIR/platform.sh"
  
  # Test detection functions exist
  type axiom_is_termux >/dev/null 2>&1 || return 1
  type axiom_is_wsl >/dev/null 2>&1 || return 1
  type axiom_is_macos >/dev/null 2>&1 || return 1
  type axiom_detect_platform >/dev/null 2>&1 || return 1
  
  # Test platform detection returns something
  local platform
  platform="$(axiom_detect_platform)"
  [ -n "$platform" ] || return 1
  
  # Test platform summary
  local summary
  summary="$(axiom_platform_summary)"
  [ -n "$summary" ] || return 1
  
  return 0
}

test_shell() {
  source "$CORE_DIR/shell.sh"
  
  # Test command_exists
  axiom_command_exists "bash" || return 1
  ! axiom_command_exists "nonexistent_command_xyz123" || return 1
  
  # Test require_command
  axiom_require_command "bash" || return 1
  
  # Test mktemp fallback
  local temp_file
  temp_file="$(axiom_mktemp)"
  [ -f "$temp_file" ] || return 1
  rm -f "$temp_file"
  
  # Test now_utc returns something
  local utc_time
  utc_time="$(axiom_now_utc)"
  [ -n "$utc_time" ] || return 1
  
  return 0
}

test_env() {
  source "$CORE_DIR/env.sh"
  
  # Create test env file
  local test_env
  test_env="$(mktemp)"
  
  cat > "$test_env" <<EOF
# Test environment
TEST_STRING="hello world"
TEST_NUMBER=123
TEST_BOOL=true
TEST_UNQUOTED=unquoted_value
# Commented line
export TEST_EXPORTED="exported value"
TEST_INLINE_COMMENT="value" # inline comment
EOF
  
  # Load the env file
  axiom_load_env_file "$test_env"
  
  # Check variables were set
  [ "${TEST_STRING:-}" = "hello world" ] || return 1
  [ "${TEST_NUMBER:-}" = "123" ] || return 1
  [ "${TEST_BOOL:-}" = "true" ] || return 1
  [ "${TEST_UNQUOTED:-}" = "unquoted_value" ] || return 1
  [ "${TEST_EXPORTED:-}" = "exported value" ] || return 1
  [ "${TEST_INLINE_COMMENT:-}" = "value" ] || return 1
  
  # Test env_get with default
  [ "$(axiom_env_get "TEST_STRING" "default")" = "hello world" ] || return 1
  [ "$(axiom_env_get "NONEXISTENT" "default")" = "default" ] || return 1
  
  # Test env_bool
  [ "$(axiom_env_bool "TEST_BOOL" "0")" = "1" ] || return 1
  [ "$(axiom_env_bool "NONEXISTENT" "1")" = "1" ] || return 1
  [ "$(axiom_env_bool "NONEXISTENT" "0")" = "0" ] || return 1
  
  # Clean up
  rm -f "$test_env"
  
  return 0
}

test_runs() {
  source "$CORE_DIR/runs.sh"
  
  # Create test run directory
  local run_dir
  run_dir="$(axiom_runs_create_dir "test" "unit")"
  
  [ -d "$run_dir" ] || return 1
  
  # Write output
  axiom_runs_write_output "$run_dir" "Test output line 1"
  axiom_runs_write_output "$run_dir" "Test output line 2"
  
  [ -f "$run_dir/output.log" ] || return 1
  grep -q "Test output line 1" "$run_dir/output.log" || return 1
  
  # Write metadata
  axiom_runs_write_metadata "$run_dir" "test" "unit" "test_command" "0" \
    "2024-01-01T00:00:00Z" "2024-01-01T00:01:00Z" "/tmp"
  
  [ -f "$run_dir/metadata.json" ] || return 1
  grep -q '"mode": "test"' "$run_dir/metadata.json" || return 1
  
  # Clean up
  rm -rf "$run_dir"
  
  return 0
}

# =============================================================================
# COCKPIT BIN TESTS (Smoke tests)
# =============================================================================

test_cockpit_bin_exists() {
  # Just check files exist and are executable
  [ -f "$COCKPIT_BIN_DIR/cockpit.sh" ] || return 1
  [ -x "$COCKPIT_BIN_DIR/cockpit.sh" ] || return 1
  
  [ -f "$COCKPIT_BIN_DIR/blux10k.sh" ] || return 1
  [ -x "$COCKPIT_BIN_DIR/blux10k.sh" ] || return 1
  
  [ -f "$COCKPIT_BIN_DIR/gpt-4o-mini.sh" ] || return 1
  [ -x "$COCKPIT_BIN_DIR/gpt-4o-mini.sh" ] || return 1
  
  [ -f "$COCKPIT_BIN_DIR/overwatch.sh" ] || return 1
  [ -x "$COCKPIT_BIN_DIR/overwatch.sh" ] || return 1
  
  return 0
}

test_cockpit_syntax() {
  # Check shell syntax without executing
  for script in "$COCKPIT_BIN_DIR"/*.sh; do
    bash -n "$script" || return 1
  done
  return 0
}

# =============================================================================
# LOCKER TESTS
# =============================================================================

test_locker_exists() {
  [ -d "$LOCKER_DIR" ] || return 1
  
  # Check for some expected tools
  [ -f "$LOCKER_DIR/orbitscan.sh" ] || return 1
  [ -f "$LOCKER_DIR/voidveil.sh" ] || return 1
  [ -f "$LOCKER_DIR/chronos_probe.sh" ] || return 1
  
  return 0
}

test_locker_syntax() {
  # Test a subset of locker tools
  local sample_scripts=(
    "orbitscan.sh"
    "voidveil.sh"
    "chronos_probe.sh"
  )
  
  for script in "${sample_scripts[@]}"; do
    if [ -f "$LOCKER_DIR/$script" ]; then
      bash -n "$LOCKER_DIR/$script" || return 1
    fi
  done
  
  return 0
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_axiom_root_scripts() {
  [ -f "$REPO_ROOT/axiom.sh" ] || return 1
  [ -x "$REPO_ROOT/axiom.sh" ] || return 1
  
  [ -f "$REPO_ROOT/launch.sh" ] || return 1
  [ -x "$REPO_ROOT/launch.sh" ] || return 1
  
  [ -f "$REPO_ROOT/py_venv.sh" ] || return 1
  [ -f "$REPO_ROOT/README.md" ] || return 1
  
  return 0
}

test_dry_run() {
  # Test axiom.sh dry-run mode
  cd "$REPO_ROOT"
  
  # This should not actually install anything
  if [ -f "cockpit/install/MANIFEST" ]; then
    # Capture, then match: `cmd | grep -q` under pipefail failed whenever grep exited early (SIGPIPE, 141).
    local out
    out="$(./axiom.sh --dry-run 2>&1)" || return 1
    [[ "$out" == *"(dry-run)"* ]] || return 1
  fi
  
  return 0
}

test_ax_router() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -m unittest "$REPO_ROOT/tests/test_ax_router.py"
}

test_ax_trifecta_status_doctor() {
  local out
  set +u
  out="$(bash -lc 'source "'"$COCKPIT_BIN_DIR"'/ax" && ax status; ax trifecta || true' 2>&1)" || return 1
  set -u

  printf '%s' "$out" | grep -q "AXIOM status (trifecta runtime)" || return 1
  printf '%s' "$out" | grep -q "\[blux10k layer\]" || return 1
  printf '%s' "$out" | grep -q "\[AXIOM layer\]" || return 1
  printf '%s' "$out" | grep -q "\[BluxGPT layer\]" || return 1
  return 0
}

# =============================================================================
# TEST GROUPS
# =============================================================================

run_core_tests() {
  echo -e "${YELLOW}Running Core Library Tests${NC}"
  echo ""
  
  run_test "constants.sh - Path resolution" test_constants
  run_test "log.sh - Logging functions" test_logging
  run_test "platform.sh - Platform detection" test_platform
  run_test "shell.sh - Shell utilities" test_shell
  run_test "env.sh - Environment handling" test_env
  run_test "runs.sh - Run telemetry" test_runs
}

run_cockpit_tests() {
  echo -e "${YELLOW}Running Cockpit Tests${NC}"
  echo ""
  
  run_test "cockpit/bin - Script existence" test_cockpit_bin_exists
  run_test "cockpit/bin - Syntax validation" test_cockpit_syntax
}

run_locker_tests() {
  echo -e "${YELLOW}Running Locker Tests${NC}"
  echo ""
  
  run_test "locker - Directory existence" test_locker_exists
  run_test "locker - Syntax validation" test_locker_syntax
}

run_integration_tests() {
  echo -e "${YELLOW}Running Integration Tests${NC}"
  echo ""
  
  run_test "Root scripts - Existence" test_axiom_root_scripts
  
  # Skip dry-run test if no manifest
  if [ -f "$REPO_ROOT/cockpit/install/MANIFEST" ]; then
    run_test "axiom.sh - Dry run mode" test_dry_run
  else
    skip_test "axiom.sh - Dry run mode" "No MANIFEST file found"
  fi
  run_test "ax - Trifecta status/doctor report" test_ax_trifecta_status_doctor
  run_test "ax - Control-plane router (python unittest)" test_ax_router
}

run_all_tests() {
  _print_header
  
  run_core_tests
  run_cockpit_tests
  run_locker_tests
  run_integration_tests
  
  _print_footer
  
  if [ $FAILED_TESTS -gt 0 ]; then
    return 1
  fi
  return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  local test_group="${1:-all}"
  local verbose="${2:-0}"
  
  export VERBOSE="$verbose"
  
  case "$test_group" in
    all)
      run_all_tests
      ;;
    core)
      _print_header
      run_core_tests
      _print_footer
      ;;
    cockpit)
      _print_header
      run_cockpit_tests
      _print_footer
      ;;
    locker)
      _print_header
      run_locker_tests
      _print_footer
      ;;
    integration)
      _print_header
      run_integration_tests
      _print_footer
      ;;
    list)
      echo "Available test groups:"
      echo "  all          - Run all tests"
      echo "  core         - Core library tests"
      echo "  cockpit      - Cockpit script tests"
      echo "  locker       - Locker tool tests"
      echo "  integration  - Integration tests"
      echo ""
      echo "Options:"
      echo "  verbose      - Show detailed output"
      echo ""
      echo "Examples:"
      echo "  ./run_tests.sh all"
      echo "  ./run_tests.sh core verbose"
      ;;
    help|--help|-h)
      cat <<EOF
AXIOM Test Suite Runner

Usage: $0 [test_group] [options]

Test Groups:
  all          Run all tests (default)
  core         Core library tests only
  cockpit      Cockpit script tests only
  locker       Locker tool tests only
  integration  Integration tests only
  list         List available test groups

Options:
  verbose      Show detailed test output
  help         Show this help message

Examples:
  $0                    # Run all tests
  $0 core               # Run core tests only
  $0 all verbose        # Run all tests with verbose output
  $0 list               # List test groups

Exit Codes:
  0 - All tests passed
  1 - Some tests failed
  2 - Invalid arguments
EOF
      return 0
      ;;
    *)
      echo -e "${RED}Error: Unknown test group '$test_group'${NC}"
      echo "Use '$0 list' to see available groups or '$0 help' for usage"
      return 2
      ;;
  esac
  
  # Return exit code based on test results
  if [ $FAILED_TESTS -gt 0 ]; then
    return 1
  fi
  return 0
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
