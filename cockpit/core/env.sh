#!/usr/bin/env bash
set -euo pipefail

# Strip inline comments while respecting quotes.
# FIXED: Added input length limit to prevent DoS
axiom_env_strip_inline_comment() {
  local line="$1"
  local out=""
  local char
  local in_single=0
  local in_double=0
  local i

  # Safety: Limit input length to prevent DoS
  local max_len=10000
  if [ ${#line} -gt $max_len ]; then
    line="${line:0:$max_len}"
    axiom_log_warn "Truncated long line in env file (exceeded ${max_len} chars)"
  fi

  for ((i = 0; i < ${#line}; i++)); do
    char="${line:$i:1}"
    if [ "$char" = "'" ] && [ "$in_double" -eq 0 ]; then
      if [ "$in_single" -eq 0 ]; then
        in_single=1
      else
        in_single=0
      fi
    elif [ "$char" = '"' ] && [ "$in_single" -eq 0 ]; then
      if [ "$in_double" -eq 0 ]; then
        in_double=1
      else
        in_double=0
      fi
    elif [ "$char" = "#" ] && [ "$in_single" -eq 0 ] && [ "$in_double" -eq 0 ]; then
      break
    fi
    out="${out}${char}"
  done

  printf '%s\n' "$out"
}

# Trim leading/trailing whitespace.
axiom_env_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

# Load environment variables from a file without overriding existing values.
axiom_load_env_file() {
  local env_file="$1"
  local line cleaned key value

  [ -f "$env_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    cleaned="$(axiom_env_strip_inline_comment "$line")"
    cleaned="$(axiom_env_trim "$cleaned")"

    if [ -z "$cleaned" ]; then
      continue
    fi

    if [ "${cleaned#export }" != "$cleaned" ]; then
      cleaned="${cleaned#export }"
      cleaned="$(axiom_env_trim "$cleaned")"
    fi

    case "$cleaned" in
      *=*)
        key="${cleaned%%=*}"
        value="${cleaned#*=}"
        key="$(axiom_env_trim "$key")"
        value="$(axiom_env_trim "$value")"
        ;;
      *)
        continue
        ;;
    esac

    if [ -z "$key" ]; then
      continue
    fi

    if [ -n "${!key+x}" ]; then
      continue
    fi

    if [ "${value:0:1}" = "'" ] && [ "${value: -1}" = "'" ]; then
      value="${value:1:${#value}-2}"
    elif [ "${value:0:1}" = '"' ] && [ "${value: -1}" = '"' ]; then
      value="${value:1:${#value}-2}"
    fi

    export "$key=$value"
  done <"$env_file"
}

# Get an environment variable with a default.
axiom_env_get() {
  local key="$1"
  local default="$2"

  if [ -n "${!key+x}" ]; then
    printf '%s\n' "${!key}"
  else
    printf '%s\n' "$default"
  fi
}

# Normalize a boolean environment variable.
axiom_env_bool() {
  local key="$1"
  local default="$2"
  local value

  if [ -n "${!key+x}" ]; then
    value="${!key}"
  else
    value="$default"
  fi

  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    1|true|yes|on)
      printf '%s\n' "1"
      ;;
    *)
      printf '%s\n' "0"
      ;;
  esac
}

# Ensure an env file exists, optionally copying from an example.
axiom_ensure_env_file() {
  local target="$1"
  local example="$2"

  if [ ! -f "$target" ]; then
    if [ -n "$example" ] && [ -f "$example" ]; then
      cp "$example" "$target"
    else
      cat <<'TEMPLATE' >"$target"
# Axiom environment configuration
TEMPLATE
    fi
  fi

  chmod 600 "$target" 2>/dev/null || true
}
