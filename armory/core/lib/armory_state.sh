#!/usr/bin/env bash
set -euo pipefail

ARMORY_STATE_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
ARMORY_CORE_DIR="$(cd -P "$ARMORY_STATE_LIB_DIR/.." >/dev/null 2>&1 && pwd -P)"
ARMORY_DIR="$(cd -P "$ARMORY_CORE_DIR/.." >/dev/null 2>&1 && pwd -P)"
ARMORY_STATE_DIR="$ARMORY_CORE_DIR/state"
ARMORY_STATE_FILE="$ARMORY_STATE_DIR/active.json"

armory_state__now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

armory_state__json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

armory_state__default_json() {
  cat <<'JSON'
{
  "active": false,
  "weapon": "",
  "profile": "",
  "engaged_at": "",
  "note": ""
}
JSON
}

armory_state__parse_value() {
  local key="$1"
  local json="$2"
  local value

  value=$(printf '%s\n' "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  value=$(printf '%s\n' "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p")
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  return 1
}

armory_state_init() {
  mkdir -p "$ARMORY_STATE_DIR"
  if [ ! -f "$ARMORY_STATE_FILE" ]; then
    armory_state__default_json >"$ARMORY_STATE_FILE"
  fi
}

armory_state_read() {
  if [ ! -r "$ARMORY_STATE_FILE" ]; then
    return 1
  fi
  cat "$ARMORY_STATE_FILE"
}

armory_state_write() {
  local json="$1"
  mkdir -p "$ARMORY_STATE_DIR"
  local tmp_file
  tmp_file="$ARMORY_STATE_DIR/.active.json.$$"
  printf '%s\n' "$json" >"$tmp_file"
  mv "$tmp_file" "$ARMORY_STATE_FILE"
}

armory_state_disarm() {
  armory_state_write "$(armory_state__default_json)"
}

armory_state_engage() {
  local weapon="$1"
  local profile="${2:-fast}"
  shift 2 || true
  local note="${*:-}"
  local engaged_at
  engaged_at="$(armory_state__now)"

  local note_escaped
  note_escaped="$(armory_state__json_escape "$note")"

  armory_state_write "$(cat <<JSON
{
  \"active\": true,
  \"weapon\": \"$weapon\",
  \"profile\": \"$profile\",
  \"engaged_at\": \"$engaged_at\",
  \"note\": \"$note_escaped\"
}
JSON
)"
}

armory_state_status() {
  local json
  if ! json="$(armory_state_read 2>/dev/null)"; then
    printf '%s\n' "ARMORY: DISARMED"
    return 0
  fi

  local active weapon profile
  active="$(armory_state__parse_value "active" "$json" || printf '%s' "false")"
  weapon="$(armory_state__parse_value "weapon" "$json" || printf '%s' "")"
  profile="$(armory_state__parse_value "profile" "$json" || printf '%s' "")"

  if [ "$active" = "true" ]; then
    printf '%s\n' "ARMORY: ENGAGED — $weapon (profile: $profile)"
  else
    printf '%s\n' "ARMORY: DISARMED"
  fi
}
