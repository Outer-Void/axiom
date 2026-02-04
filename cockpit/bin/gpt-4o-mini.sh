#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
COCKPIT_DIR="$(cd -P -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"

source "${COCKPIT_DIR}/core/constants.sh"
source "${COCKPIT_DIR}/core/shell.sh"
source "${COCKPIT_DIR}/core/log.sh"
source "${COCKPIT_DIR}/core/platform.sh"
source "${COCKPIT_DIR}/core/env.sh"
source "${COCKPIT_DIR}/core/runs.sh"

CONFIG_DIR="$(axiom_config_dir)"
ENV_FILE="${CONFIG_DIR}/.env"
ENV_EXAMPLE_FILE="${CONFIG_DIR}/.env.example"

EXIT_OK=0
EXIT_MISSING_DEP=10
EXIT_CONFIG_ERROR=20
EXIT_NETWORK_ERROR=30

JSON_MODE=0
ONLY_TEST=0

RUN_DIR=""
RUN_OUTPUT_TEXT=""
RUN_HTTP_CODE=""
RUN_LATENCY_MS=""
STARTED_AT=""
COMMAND_LINE=""

log_info() {
  if [[ "$JSON_MODE" -eq 0 ]]; then
    axiom_log_info "$@"
  fi
}

log_warn() {
  if [[ "$JSON_MODE" -eq 0 ]]; then
    axiom_log_warn "$@"
  fi
}

log_error() {
  if [[ "$JSON_MODE" -eq 0 ]]; then
    axiom_log_error "$@"
  fi
}

now_ms() {
  local ms
  ms="$(date +%s%3N 2>/dev/null || true)"
  if [[ "$ms" =~ ^[0-9]{13,}$ ]]; then
    printf '%s\n' "$ms"
  else
    ms="$(date +%s)"
    printf '%s\n' "$((ms * 1000))"
  fi
}

json_escape() {
  axiom_runs_json_escape "$1"
}

emit_json_success() {
  local http_code latency_ms
  http_code="${RUN_HTTP_CODE:-0}"
  latency_ms="${RUN_LATENCY_MS:-0}"
  if ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
    http_code=0
  fi
  if ! [[ "$latency_ms" =~ ^[0-9]+$ ]]; then
    latency_ms=0
  fi
  printf '{"ok":true,"model":"%s","base_url":"%s","latency_ms":%s,"http_code":%s}\n' \
    "$(json_escape "${OPENAI_MODEL:-gpt-4o-mini}")" \
    "$(json_escape "${OPENAI_BASE_URL:-https://api.openai.com/v1}")" \
    "$latency_ms" \
    "$http_code"
}

emit_json_error() {
  local error_message="$1"
  local http_code
  http_code="${RUN_HTTP_CODE:-0}"
  if ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
    http_code=0
  fi
  printf '{"ok":false,"error":"%s","http_code":%s}\n' \
    "$(json_escape "$error_message")" \
    "$http_code"
}

write_run_metadata() {
  local exit_code="$1"
  local ended_at
  ended_at="$(axiom_now_utc)"
  if [[ -n "$RUN_DIR" ]]; then
    axiom_runs_write_metadata "$RUN_DIR" "ai" "gpt-4o-mini" "$COMMAND_LINE" "$exit_code" "$STARTED_AT" "$ended_at"
  fi
}

on_exit() {
  local exit_code=$?
  write_run_metadata "$exit_code"
}

trap on_exit EXIT

install_packages() {
  local platform
  platform="$(axiom_detect_platform)"

  local missing=()
  for dep in curl jq; do
    if ! axiom_command_exists "$dep"; then
      missing+=("$dep")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    if axiom_command_exists "update-ca-certificates" || axiom_command_exists "trust" || [[ "$platform" == "macos" ]]; then
      :
    fi
    return 0
  fi

  log_info "Installing dependencies: ${missing[*]}"

  case "$platform" in
    termux)
      pkg update -y
      pkg install -y curl jq ca-certificates
      ;;
    linux)
      if axiom_command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y curl jq ca-certificates
      elif axiom_command_exists dnf; then
        sudo dnf install -y curl jq ca-certificates
      elif axiom_command_exists yum; then
        sudo yum install -y curl jq ca-certificates
      elif axiom_command_exists pacman; then
        sudo pacman -Sy --noconfirm curl jq ca-certificates
      elif axiom_command_exists zypper; then
        sudo zypper install -y curl jq ca-certificates
      else
        log_warn "No supported package manager found. Please install: curl jq ca-certificates."
      fi
      ;;
    macos)
      if axiom_command_exists brew; then
        brew install curl jq
      else
        log_warn "Homebrew not found. Please install: curl jq (and ensure ca-certificates are present)."
      fi
      ;;
    windows)
      if axiom_command_exists winget; then
        winget install --silent --accept-source-agreements --accept-package-agreements curl || log_warn "winget install failed"
        winget install --silent --accept-source-agreements --accept-package-agreements jq || log_warn "winget install failed"
      elif axiom_command_exists choco; then
        choco install -y curl jq || log_warn "choco install failed"
      else
        log_warn "No Windows package manager detected. Please install curl and jq manually."
      fi
      ;;
    *)
      log_warn "Unknown platform. Please install: curl jq ca-certificates."
      ;;
  esac
}

require_dependencies() {
  local dep
  for dep in curl jq; do
    if ! axiom_command_exists "$dep"; then
      return 1
    fi
  done
  return 0
}

ensure_api_key() {
  local api_key_input=""
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    return 0
  fi

  if ! axiom_is_tty_stdin; then
    return 1
  fi

  log_info "OPENAI_API_KEY is missing."
  printf "%s Enter OpenAI API key (input hidden): " "[gpt-4o-mini]"
  read -r -s api_key_input
  printf "\n"
  if [[ -z "$api_key_input" ]]; then
    log_warn "No API key entered."
    return 1
  fi

  OPENAI_API_KEY="$api_key_input"
  return 0
}

run_test() {
  local base_url model timeout payload
  local max_output_tokens resp_file http_code output_text
  local start_ms end_ms latency_ms

  base_url="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
  model="${OPENAI_MODEL:-gpt-4o-mini}"
  timeout="${OPENAI_TIMEOUT:-60}"
  max_output_tokens="${OPENAI_MAX_OUTPUT_TOKENS:-500}"

  if ! [[ "$max_output_tokens" =~ ^[0-9]+$ ]]; then
    max_output_tokens=500
  fi

  payload="$(jq -n --arg model "$model" --arg input "Say 'ok' and nothing else." --argjson max_output_tokens "$max_output_tokens" '{model:$model,input:$input,max_output_tokens:$max_output_tokens}')"

  resp_file="$(axiom_mktemp)"
  start_ms="$(now_ms)"
  http_code="$(curl -sS --max-time "$timeout" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -o "$resp_file" \
    -w "%{http_code}" \
    "${base_url}/responses" \
    -d "$payload" || true)"
  end_ms="$(now_ms)"
  latency_ms=$((end_ms - start_ms))

  output_text="$(jq -r '.output_text // .output[0].content[0].text // empty' "$resp_file" 2>/dev/null || true)"

  rm -f "$resp_file"

  RUN_HTTP_CODE="$http_code"
  RUN_LATENCY_MS="$latency_ms"
  RUN_OUTPUT_TEXT="$output_text"

  if [[ "$http_code" == "200" && -n "$output_text" ]]; then
    return 0
  fi

  return 1
}

print_usage() {
  if [[ "$JSON_MODE" -eq 1 ]]; then
    return 0
  fi

  cat <<USAGE
[gpt-4o-mini] How to use
[gpt-4o-mini] Config file: ${ENV_FILE}
[gpt-4o-mini] Re-run test: ${SCRIPT_DIR}/gpt-4o-mini.sh --test
[gpt-4o-mini] Example:
[gpt-4o-mini]   (set -a; \
[gpt-4o-mini]    while IFS= read -r line; do \
[gpt-4o-mini]      case "\${line}" in \
[gpt-4o-mini]        ''|\#*) continue ;; \
[gpt-4o-mini]        OPENAI_API_KEY=*|OPENAI_MODEL=*|OPENAI_BASE_URL=*|OPENAI_TIMEOUT=*|OPENAI_MAX_OUTPUT_TOKENS=*) export "\${line}" ;; \
[gpt-4o-mini]      esac; \
[gpt-4o-mini]    done < "${ENV_FILE}"; \
[gpt-4o-mini]    set +a; \
[gpt-4o-mini]    curl -sS -H "Content-Type: application/json" \
[gpt-4o-mini]      -H "Authorization: Bearer \${OPENAI_API_KEY}" \
[gpt-4o-mini]      "\${OPENAI_BASE_URL:-https://api.openai.com/v1}/responses" \
[gpt-4o-mini]      -d "{\"model\":\"\${OPENAI_MODEL:-gpt-4o-mini}\",\"input\":\"Hello\"}" | jq -r '.output_text // .output[0].content[0].text')
USAGE
}

main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --test)
        ONLY_TEST=1
        ;;
      --json)
        JSON_MODE=1
        ;;
      --help|-h)
        print_usage
        return 0
        ;;
    esac
  done

  COMMAND_LINE="$0 $*"
  STARTED_AT="$(axiom_now_utc)"
  RUN_DIR="$(axiom_runs_create_dir "ai" "gpt-4o-mini")"

  axiom_ensure_env_file "$ENV_FILE" "$ENV_EXAMPLE_FILE"
  axiom_load_env_file "$ENV_FILE"

  OPENAI_API_KEY="${OPENAI_API_KEY:-}"
  OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
  OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
  OPENAI_TIMEOUT="${OPENAI_TIMEOUT:-60}"
  OPENAI_MAX_OUTPUT_TOKENS="${OPENAI_MAX_OUTPUT_TOKENS:-500}"

  if [[ "$ONLY_TEST" -eq 0 ]]; then
    if [[ "$JSON_MODE" -eq 1 ]]; then
      install_packages >&2
    else
      install_packages
    fi
  fi

  if ! require_dependencies; then
    log_error "Missing dependencies: curl and jq are required."
    axiom_runs_write_output "$RUN_DIR" "Error: Missing dependencies: curl and jq are required."
    if [[ "$JSON_MODE" -eq 1 ]]; then
      emit_json_error "Missing dependencies: curl and jq are required."
    fi
    return "$EXIT_MISSING_DEP"
  fi

  if ! ensure_api_key; then
    log_error "OPENAI_API_KEY is missing."
    axiom_runs_write_output "$RUN_DIR" "Error: OPENAI_API_KEY is missing."
    if [[ "$JSON_MODE" -eq 1 ]]; then
      emit_json_error "OPENAI_API_KEY is missing."
    else
      print_usage
    fi
    return "$EXIT_CONFIG_ERROR"
  fi

  if run_test; then
    if [[ -n "$RUN_OUTPUT_TEXT" ]]; then
      axiom_runs_log_ai "$RUN_OUTPUT_TEXT"
      axiom_runs_write_output "$RUN_DIR" "$RUN_OUTPUT_TEXT"
    fi
    if [[ "$JSON_MODE" -eq 1 ]]; then
      emit_json_success
    else
      log_info "Connectivity test passed."
      print_usage
    fi
    return "$EXIT_OK"
  fi

  if [[ -n "$RUN_OUTPUT_TEXT" ]]; then
    axiom_runs_log_ai "$RUN_OUTPUT_TEXT"
    axiom_runs_write_output "$RUN_DIR" "$RUN_OUTPUT_TEXT"
  fi

  local error_message
  case "${RUN_HTTP_CODE:-}" in
    401)
      error_message="Unauthorized. Check OPENAI_API_KEY in ${ENV_FILE}."
      ;;
    404)
      error_message="Endpoint not found. Check OPENAI_BASE_URL (${OPENAI_BASE_URL})."
      ;;
    429)
      error_message="Rate limited. Wait and try again or check account limits."
      ;;
    0|"")
      error_message="Network error. Check connectivity and proxy settings."
      ;;
    *)
      error_message="Unexpected response. Verify OPENAI_MODEL (${OPENAI_MODEL}) and OPENAI_BASE_URL (${OPENAI_BASE_URL})."
      ;;
  esac

  if [[ "$JSON_MODE" -eq 1 ]]; then
    emit_json_error "$error_message"
  else
    log_warn "Connectivity test failed (HTTP ${RUN_HTTP_CODE:-unknown})."
    log_warn "$error_message"
    print_usage
  fi
  axiom_runs_write_output "$RUN_DIR" "Error: $error_message"

  if [[ "${RUN_HTTP_CODE:-}" == "401" ]]; then
    return "$EXIT_CONFIG_ERROR"
  fi

  return "$EXIT_NETWORK_ERROR"
}

main "$@"
