#!/usr/bin/env bash
set -euo pipefail

ARMORY_REGISTRY_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
ARMORY_CORE_DIR="$(cd -P "$ARMORY_REGISTRY_LIB_DIR/.." >/dev/null 2>&1 && pwd -P)"
ARMORY_DIR="$(cd -P "$ARMORY_CORE_DIR/.." >/dev/null 2>&1 && pwd -P)"
ARMORY_WEAPONS_DIR="$ARMORY_DIR/weapons"

armory_registry_list() {
  local dir
  if [ ! -d "$ARMORY_WEAPONS_DIR" ]; then
    return 0
  fi

  for dir in "$ARMORY_WEAPONS_DIR"/*; do
    if [ -d "$dir" ] && [ -f "$dir/manifest.json" ]; then
      basename "$dir"
    fi
  done | sort
}

armory_registry_has() {
  local weapon="$1"
  if [ -f "$ARMORY_WEAPONS_DIR/$weapon/manifest.json" ]; then
    return 0
  fi
  return 1
}

armory_registry_manifest() {
  local weapon="$1"
  local manifest="$ARMORY_WEAPONS_DIR/$weapon/manifest.json"
  if [ ! -r "$manifest" ]; then
    return 1
  fi
  cat "$manifest"
}
