#!/usr/bin/env bash
set -euo pipefail

ARMORY_UI_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
ARMORY_CORE_DIR="$(cd -P "$ARMORY_UI_LIB_DIR/.." >/dev/null 2>&1 && pwd -P)"

# shellcheck disable=SC1091
. "$ARMORY_CORE_DIR/lib/armory_state.sh"

armory_ui_kv() {
  local key="$1"
  local value="$2"
  printf '%-18s %s\n' "$key" "$value"
}

armory_ui_banner() {
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
    printf '%s\n' "ARMORY: ENGAGED — $weapon (profile: $profile) — EXECUTION: INTERCEPTED"
  else
    printf '%s\n' "ARMORY: DISARMED"
  fi
}
