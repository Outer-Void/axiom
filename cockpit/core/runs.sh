#!/usr/bin/env bash
set -euo pipefail

# Flight recorder helpers.

axiom_runs_dir_path() {
  axiom_runs_dir
}

axiom_runs_create_dir() {
  local mode="$1"
  local action="$2"
  local runs_dir run_stamp run_dir

  runs_dir="$(axiom_runs_dir_path)"
  mkdir -p "$runs_dir"

  run_stamp="$(date +"%Y%m%d_%H%M%S")"
  run_dir="$runs_dir/${run_stamp}_${mode}_${action}"
  mkdir -p "$run_dir"

  printf '%s\n' "$run_dir"
}

axiom_runs_write_output() {
  local run_dir="$1"
  local text="$2"

  mkdir -p "$run_dir"
  printf '%s\n' "$text" >>"$run_dir/output.log"
}

axiom_runs_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

axiom_runs_write_metadata() {
  local run_dir="$1"
  local mode="$2"
  local action="$3"
  local command="$4"
  local exit_code="$5"
  local started="$6"
  local ended="$7"
  local cwd="${8:-}"
  local platform

  mkdir -p "$run_dir"

  if [ -z "$cwd" ]; then
    cwd="$(pwd -P)"
  fi

  platform="$(axiom_detect_platform)"

  cat <<EOF_JSON >"$run_dir/metadata.json"
{
  "mode": "$(axiom_runs_json_escape "$mode")",
  "action": "$(axiom_runs_json_escape "$action")",
  "command": "$(axiom_runs_json_escape "$command")",
  "exit_code": "$(axiom_runs_json_escape "$exit_code")",
  "platform": "$(axiom_runs_json_escape "$platform")",
  "cwd": "$(axiom_runs_json_escape "$cwd")",
  "started_at": "$(axiom_runs_json_escape "$started")",
  "ended_at": "$(axiom_runs_json_escape "$ended")"
}
EOF_JSON
}

axiom_runs_log_ai() {
  local text="$1"
  local runs_dir

  runs_dir="$(axiom_runs_dir_path)"
  mkdir -p "$runs_dir"
  printf '%s\n' "$text" >>"$runs_dir/ai_output.log"
}
