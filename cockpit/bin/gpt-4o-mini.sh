#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[gpt-4o-mini]"

log() {
  printf "%s %s\n" "$LOG_PREFIX" "$*"
}

warn() {
  printf "%s WARNING: %s\n" "$LOG_PREFIX" "$*" >&2
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COCKPIT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${COCKPIT_DIR}/config"
ENV_FILE="${CONFIG_DIR}/.env"

is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux/files/usr" ]]
}

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null
}

platform_name() {
  local uname_s
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin) echo "macos" ;;
    Linux)
      if is_termux; then
        echo "termux"
      else
        echo "linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

ensure_env_file() {
  mkdir -p "$CONFIG_DIR"
  if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "${CONFIG_DIR}/.env.example" ]]; then
      cp "${CONFIG_DIR}/.env.example" "$ENV_FILE"
      log "Created config from .env.example."
    else
      {
        echo "# OpenAI configuration"
        echo "# OPENAI_API_KEY="
        echo "# OPENAI_MODEL=gpt-4o-mini"
        echo "# OPENAI_BASE_URL=https://api.openai.com/v1"
        echo "# OPENAI_TIMEOUT=60"
        echo "# OPENAI_MAX_OUTPUT_TOKENS=500"
      } > "$ENV_FILE"
      log "Created new config file."
    fi
  fi

  if chmod 600 "$ENV_FILE" 2>/dev/null; then
    :
  else
    warn "Unable to set permissions on ${ENV_FILE}."
  fi
}

strip_quotes() {
  local value="$1"
  if [[ "$value" =~ ^\".*\"$ ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf "%s" "$value"
}

read_env() {
  local line key value
  OPENAI_API_KEY=""
  OPENAI_MODEL=""
  OPENAI_BASE_URL=""
  OPENAI_TIMEOUT=""
  OPENAI_MAX_OUTPUT_TOKENS=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      if [[ "$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$ ]]; then
        value="$(strip_quotes "$value")"
      else
        value="$(strip_quotes "$value")"
        value="${value%%#*}"
        value="${value%"${value##*[![:space:]]}"}"
      fi
      case "$key" in
        OPENAI_API_KEY) OPENAI_API_KEY="$value" ;;
        OPENAI_MODEL) OPENAI_MODEL="$value" ;;
        OPENAI_BASE_URL) OPENAI_BASE_URL="$value" ;;
        OPENAI_TIMEOUT) OPENAI_TIMEOUT="$value" ;;
        OPENAI_MAX_OUTPUT_TOKENS) OPENAI_MAX_OUTPUT_TOKENS="$value" ;;
        *) : ;;
      esac
    fi
  done < "$ENV_FILE"
}

update_env_key() {
  local key="$1"
  local value="$2"
  local file="$3"
  local tmp
  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" 'BEGIN{done=0}
      $0 ~ "^[[:space:]]*"k"=" {
        print k"="v
        done=1
        next
      }
      {print}
      END{}
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    printf "%s=%s\n" "$key" "$value" >> "$file"
  fi
}

ensure_defaults() {
  local updated=0
  if [[ -z "$OPENAI_MODEL" ]]; then
    OPENAI_MODEL="gpt-4o-mini"
    update_env_key "OPENAI_MODEL" "$OPENAI_MODEL" "$ENV_FILE"
    updated=1
  fi
  if [[ -z "$OPENAI_BASE_URL" ]]; then
    OPENAI_BASE_URL="https://api.openai.com/v1"
    update_env_key "OPENAI_BASE_URL" "$OPENAI_BASE_URL" "$ENV_FILE"
    updated=1
  fi
  if [[ -z "$OPENAI_TIMEOUT" ]]; then
    OPENAI_TIMEOUT="60"
    update_env_key "OPENAI_TIMEOUT" "$OPENAI_TIMEOUT" "$ENV_FILE"
    updated=1
  fi
  if [[ -z "$OPENAI_MAX_OUTPUT_TOKENS" ]]; then
    OPENAI_MAX_OUTPUT_TOKENS="500"
    update_env_key "OPENAI_MAX_OUTPUT_TOKENS" "$OPENAI_MAX_OUTPUT_TOKENS" "$ENV_FILE"
    updated=1
  fi
  if [[ "$updated" -eq 1 ]]; then
    log "Updated config defaults in ${ENV_FILE}."
  fi
}

ensure_api_key() {
  if [[ -n "$OPENAI_API_KEY" ]]; then
    return 0
  fi

  log "OPENAI_API_KEY is missing."
  printf "%s Enter OpenAI API key (input hidden): " "$LOG_PREFIX"
  read -r -s api_key_input
  printf "\n"
  if [[ -z "$api_key_input" ]]; then
    warn "No API key entered."
    return 1
  fi

  local save_answer
  printf "%s Save key to %s? [Y/n]: " "$LOG_PREFIX" "$ENV_FILE"
  read -r save_answer
  save_answer="${save_answer:-Y}"
  if [[ "$save_answer" =~ ^[Yy]$ ]]; then
    update_env_key "OPENAI_API_KEY" "$api_key_input" "$ENV_FILE"
    if chmod 600 "$ENV_FILE" 2>/dev/null; then
      :
    else
      warn "Unable to set permissions on ${ENV_FILE}."
    fi
    log "Saved API key to config."
  else
    log "Using API key for this session only."
  fi
  OPENAI_API_KEY="$api_key_input"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_packages() {
  local platform
  platform="$(platform_name)"

  local missing=()
  for dep in curl jq; do
    if ! command_exists "$dep"; then
      missing+=("$dep")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    if command_exists "update-ca-certificates" || command_exists "trust" || [[ "$platform" == "macos" ]]; then
      :
    fi
    return 0
  fi

  log "Installing dependencies: ${missing[*]}"

  case "$platform" in
    termux)
      pkg update -y
      pkg install -y curl jq ca-certificates
      ;;
    linux)
      if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y curl jq ca-certificates
      elif command_exists dnf; then
        sudo dnf install -y curl jq ca-certificates
      elif command_exists yum; then
        sudo yum install -y curl jq ca-certificates
      elif command_exists pacman; then
        sudo pacman -Sy --noconfirm curl jq ca-certificates
      elif command_exists zypper; then
        sudo zypper install -y curl jq ca-certificates
      else
        warn "No supported package manager found. Please install: curl jq ca-certificates."
      fi
      ;;
    macos)
      if command_exists brew; then
        brew install curl jq
      else
        warn "Homebrew not found. Please install: curl jq (and ensure ca-certificates are present)."
      fi
      ;;
    windows)
      if command_exists winget; then
        winget install --silent --accept-source-agreements --accept-package-agreements curl || warn "winget install failed"
        winget install --silent --accept-source-agreements --accept-package-agreements jq || warn "winget install failed"
      elif command_exists choco; then
        choco install -y curl jq || warn "choco install failed"
      else
        warn "No Windows package manager detected. Please install curl and jq manually."
      fi
      ;;
    *)
      warn "Unknown platform. Please install: curl jq ca-certificates."
      ;;
  esac
}

run_test() {
  local base_url="$OPENAI_BASE_URL"
  local model="$OPENAI_MODEL"
  local timeout="$OPENAI_TIMEOUT"

  if [[ -z "$base_url" ]]; then
    base_url="https://api.openai.com/v1"
  fi
  if [[ -z "$model" ]]; then
    model="gpt-4o-mini"
  fi
  if [[ -z "$timeout" ]]; then
    timeout="60"
  fi

  local payload
  local max_output_tokens="${OPENAI_MAX_OUTPUT_TOKENS:-500}"
  if ! [[ "$max_output_tokens" =~ ^[0-9]+$ ]]; then
    max_output_tokens=500
  fi
  payload="$(jq -n --arg model "$model" --arg input "Say 'ok' and nothing else." --argjson max_output_tokens "$max_output_tokens" '{model:$model,input:$input,max_output_tokens:$max_output_tokens}')"

  local resp_file http_code output_text
  resp_file="$(mktemp)"
  http_code="$(curl -sS --max-time "$timeout" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -o "$resp_file" \
    -w "%{http_code}" \
    "${base_url}/responses" \
    -d "$payload" || true)"

  output_text="$(jq -r '.output_text // .output[0].content[0].text // empty' "$resp_file" 2>/dev/null || true)"

  rm -f "$resp_file"

  if [[ "$http_code" == "200" && -n "$output_text" ]]; then
    log "Connectivity test passed."
    return 0
  fi

  warn "Connectivity test failed (HTTP ${http_code:-unknown})."
  if [[ -z "$OPENAI_API_KEY" ]]; then
    warn "API key is missing."
  fi
  if [[ "$http_code" == "401" ]]; then
    warn "Unauthorized. Check OPENAI_API_KEY in ${ENV_FILE}."
  elif [[ "$http_code" == "404" ]]; then
    warn "Endpoint not found. Check OPENAI_BASE_URL (${base_url})."
  elif [[ "$http_code" == "429" ]]; then
    warn "Rate limited. Wait and try again or check account limits."
  elif [[ "$http_code" == "0" || -z "$http_code" ]]; then
    warn "Network error. Check connectivity and proxy settings."
  else
    warn "Unexpected response. Verify OPENAI_MODEL (${model}) and OPENAI_BASE_URL (${base_url})."
  fi
  return 1
}

print_usage() {
  cat <<USAGE
${LOG_PREFIX} How to use
${LOG_PREFIX} Config file: ${ENV_FILE}
${LOG_PREFIX} Re-run test: ${SCRIPT_DIR}/gpt-4o-mini.sh --test
${LOG_PREFIX} Example:
${LOG_PREFIX}   (set -a; \
${LOG_PREFIX}    while IFS= read -r line; do \
${LOG_PREFIX}      case "$line" in \
${LOG_PREFIX}        ''|\#*) continue ;; \
${LOG_PREFIX}        OPENAI_API_KEY=*|OPENAI_MODEL=*|OPENAI_BASE_URL=*|OPENAI_TIMEOUT=*|OPENAI_MAX_OUTPUT_TOKENS=*) export "$line" ;; \
${LOG_PREFIX}      esac; \
${LOG_PREFIX}    done < "${ENV_FILE}"; \
${LOG_PREFIX}    set +a; \
${LOG_PREFIX}    curl -sS -H "Content-Type: application/json" \
${LOG_PREFIX}      -H "Authorization: Bearer \${OPENAI_API_KEY}" \
${LOG_PREFIX}      \"\${OPENAI_BASE_URL:-https://api.openai.com/v1}/responses\" \
${LOG_PREFIX}      -d "{\"model\":\"\${OPENAI_MODEL:-gpt-4o-mini}\",\"input\":\"Hello\"}" | jq -r '.output_text // .output[0].content[0].text')
USAGE
}

main() {
  local only_test=0
  if [[ "${1:-}" == "--test" ]]; then
    only_test=1
  fi

  ensure_env_file
  read_env
  ensure_defaults

  if [[ "$only_test" -eq 0 ]]; then
    install_packages
  fi

  if ! ensure_api_key; then
    warn "Cannot proceed without API key."
    print_usage
    return 1
  fi

  if run_test; then
    print_usage
  else
    print_usage
    return 1
  fi
}

main "$@"
