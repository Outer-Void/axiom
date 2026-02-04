#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# Overwatch: Sentinel / Night Ops
# Self-contained cross-platform TUI cockpit
# - Left: modes (Observe / Files / Operate / Terminal / Signal / Config / About)
# - Right: terminal pane (responsive; stacked or toggled in narrow mode)
# - Global cwd shared across Files/Operate/Terminal
# - Runs logging: runs/<ts>_<mode>_<action>/{output.log,metadata.json}
# -------------------------------
# How to test:
#   ./cockpit/bin/overwatch.sh
#   Resize terminal to <120 columns (or use a narrow Termux session) to trigger narrow mode.
#   Keybinds: q quit, t toggle terminal (narrow mode), / search, tab cycle panes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
COCKPIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${COCKPIT_DIR}/.." && pwd -P)"
OVERWATCH_ACTIVE=0

detect_platform() {
  local platform="unknown"

  # Termux detection
  if [ -n "${TERMUX_VERSION-}" ] || [ -d "/data/data/com.termux" ] || [[ "${PREFIX-}" == *com.termux* ]] || [[ "$(uname -o 2>/dev/null || true)" == "Android" ]]; then
    platform="termux"
  # WSL2 detection
  elif [ -r /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    platform="wsl2"
  # macOS detection
  elif [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
    platform="macos"
  # Linux detection
  elif [[ "$(uname -s 2>/dev/null || true)" == "Linux" ]]; then
    platform="linux"
  # Windows (Git Bash, Cygwin, MSYS)
  elif [[ "$(uname -s 2>/dev/null || true)" == "MINGW"* ]] || [[ "$(uname -s 2>/dev/null || true)" == "CYGWIN"* ]] || [[ "$(uname -s 2>/dev/null || true)" == "MSYS"* ]]; then
    platform="windows"
  fi

  echo "$platform"
}

PLATFORM="$(detect_platform)"

# Normalize with realpath if available
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_DIR="$(realpath "${SCRIPT_DIR}")"
  COCKPIT_DIR="$(realpath "${COCKPIT_DIR}")"
  REPO_ROOT="$(realpath "${REPO_ROOT}")"
elif command -v greadlink >/dev/null 2>&1; then
  SCRIPT_DIR="$(greadlink -f "${SCRIPT_DIR}" 2>/dev/null || echo "${SCRIPT_DIR}")"
  COCKPIT_DIR="$(greadlink -f "${COCKPIT_DIR}" 2>/dev/null || echo "${COCKPIT_DIR}")"
  REPO_ROOT="$(greadlink -f "${REPO_ROOT}" 2>/dev/null || echo "${REPO_ROOT}")"
fi

RUNS_DIR="${COCKPIT_DIR}/runs"
CONFIG_DIR="${COCKPIT_DIR}/config"
ENV_FILE="${CONFIG_DIR}/.env"
LOCKER_DIR="${REPO_ROOT}/locker"

# Optional platform-specific env override
PLATFORM_CONFIG="${CONFIG_DIR}/.env.${PLATFORM}"
if [ -f "${PLATFORM_CONFIG}" ]; then
  ENV_FILE="${PLATFORM_CONFIG}"
fi

mkdir -p "${RUNS_DIR}" "${CONFIG_DIR}" 2>/dev/null || true

# Platform-specific python command default
PYTHON_CMD="python3"
if [ "${PLATFORM}" = "windows" ]; then
  PYTHON_CMD="python"
fi

disable_mouse_reporting() {
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1015l\e[?25h' || true
}

restore_terminal() {
  disable_mouse_reporting
  stty sane 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  printf '\e[0m' || true
}

cleanup() {
  if [ "${OVERWATCH_ACTIVE}" -eq 1 ]; then
    restore_terminal
    jobs -p | xargs kill -9 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

check_python() {
  if ! command -v "${PYTHON_CMD}" >/dev/null 2>&1; then
    echo "Error: Python is required but not found." >&2
    echo "Platform: ${PLATFORM}" >&2
    case "$PLATFORM" in
      termux) echo "Install with: pkg install python3" >&2 ;;
      macos)  echo "Install with: brew install python3" >&2 ;;
      linux|wsl2) echo "Install with: sudo apt install python3" >&2 ;;
      windows) echo "Install from: https://www.python.org/downloads/windows/" >&2 ;;
      *) echo "Install Python 3 and ensure it is in PATH." >&2 ;;
    esac
    exit 1
  fi
}

usage() {
  cat <<'USAGE'
Overwatch: Sentinel / Night Ops
Usage: overwatch.sh [--help] [--self-test]

Options:
  --help       Show this help message.
  --self-test  Print environment info, ensure runs dir exists, list locker tools.
USAGE
}

write_run_metadata() {
  local run_dir="$1"
  local mode="$2"
  local action="$3"
  local command="$4"
  local cwd="$5"
  local exit_code="$6"
  local started="$7"
  local ended="$8"
  cat > "${run_dir}/metadata.json" <<META
{
  "mode": "${mode}",
  "action": "${action}",
  "command": "${command}",
  "exit_code": ${exit_code},
  "platform": "${PLATFORM}",
  "cwd": "${cwd}",
  "started_at": "${started}",
  "ended_at": "${ended}"
}
META
}

make_run_dir() {
  local mode="$1"
  local action="$2"
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local run_dir="${RUNS_DIR}/${ts}_${mode}_${action}"
  mkdir -p "${run_dir}"
  echo "${run_dir}"
}

self_test() {
  echo "Overwatch self-test"
  echo "Platform: ${PLATFORM}"
  echo "Script: ${SCRIPT_DIR}"
  echo "Cockpit: ${COCKPIT_DIR}"
  echo "Repo: ${REPO_ROOT}"
  echo "Runs: ${RUNS_DIR}"
  echo "Config: ${ENV_FILE}"
  mkdir -p "${RUNS_DIR}"
  echo "Locker tools:"
  if [ -d "${LOCKER_DIR}" ]; then
    ls -1 "${LOCKER_DIR}"/*.sh 2>/dev/null | sed 's#.*/##' || echo "  (none)"
  else
    echo "  (locker dir missing)"
  fi
  echo "Python: ${PYTHON_CMD}"
}

run_fallback_mode() {
  echo "Textual not available. Running fallback mode."
  echo "Platform: ${PLATFORM}"
  echo "Tip: install Textual with: ${PYTHON_CMD} -m pip install textual"
  echo ""

  local cwd="${REPO_ROOT}"

  show_config_status() {
    local env_path="${ENV_FILE}"
    local display_path="${env_path}"
    if [ ! -f "${env_path}" ] && [ -f "${CONFIG_DIR}/.env.example" ]; then
      display_path="${CONFIG_DIR}/.env.example"
    fi
    echo "Config file: ${display_path}"
    if [ -f "${display_path}" ]; then
      if grep -q '^OPENAI_API_KEY=' "${display_path}" 2>/dev/null; then
        echo "OPENAI_API_KEY: set"
      else
        echo "OPENAI_API_KEY: not set"
      fi
      if grep -q '^OPENAI_MODEL=' "${display_path}" 2>/dev/null; then
        echo "OPENAI_MODEL: set"
      else
        echo "OPENAI_MODEL: not set"
      fi
    else
      echo "No config file found."
    fi
  }

  list_runs() {
    ls -1t "${RUNS_DIR}" 2>/dev/null | head -n 50 || echo "No runs yet."
  }

  view_run() {
    printf "Run name> "
    read -r run_name
    [ -z "${run_name}" ] && return
    local run_dir="${RUNS_DIR}/${run_name}"
    if [ ! -d "${run_dir}" ]; then
      echo "Run not found: ${run_name}"
      return
    fi
    [ -f "${run_dir}/metadata.json" ] && cat "${run_dir}/metadata.json"
    echo "---- output ----"
    [ -f "${run_dir}/output.log" ] && tail -n 200 "${run_dir}/output.log" || echo "No output.log"
  }

  run_command_logged() {
    local cmd="$1"
    local run_dir
    run_dir="$(make_run_dir "terminal" "shell")"
    local out="${run_dir}/output.log"
    local started
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    set +e
    (cd "${cwd}" && bash -lc "${cmd}") >"${out}" 2>&1
    local exit_code=$?
    set -e
    local ended
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    write_run_metadata "${run_dir}" "terminal" "shell" "${cmd}" "${cwd}" "${exit_code}" "${started}" "${ended}"
    tail -n 200 "${out}"
  }

  run_tool_logged() {
    local tool="$1"
    local args="$2"
    local run_dir
    run_dir="$(make_run_dir "operate" "${tool%.*}")"
    local out="${run_dir}/output.log"
    local started
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    set +e
    (cd "${cwd}" && bash -lc "${LOCKER_DIR}/${tool} ${args}") >"${out}" 2>&1
    local exit_code=$?
    set -e
    local ended
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    write_run_metadata "${run_dir}" "operate" "${tool%.*}" "${LOCKER_DIR}/${tool} ${args}" "${cwd}" "${exit_code}" "${started}" "${ended}"
    tail -n 200 "${out}"
  }

  while true; do
    echo ""
    echo "OVERWATCH (Fallback)"
    echo "CWD: ${cwd}"
    echo "1) List runs"
    echo "2) View run details"
    echo "3) List locker tools"
    echo "4) Run locker tool"
    echo "5) Run shell command"
    echo "6) Set current directory"
    echo "7) Config status"
    echo "q) Quit"
    printf "> "
    read -r sel
    case "${sel:-}" in
      1)
        list_runs
        ;;
      2)
        view_run
        ;;
      3)
        if [ -d "${LOCKER_DIR}" ]; then
          ls -1 "${LOCKER_DIR}"/*.sh 2>/dev/null | sed 's#.*/##' || echo "No tools."
        else
          echo "No locker directory at ${LOCKER_DIR}"
        fi
        ;;
      4)
        printf "tool> "
        read -r tool
        [ -z "${tool}" ] && continue
        if [ ! -f "${LOCKER_DIR}/${tool}" ]; then
          echo "Tool not found: ${tool}"
          continue
        fi
        printf "args> "
        read -r args
        run_tool_logged "${tool}" "${args}"
        ;;
      5)
        printf "cmd> "
        read -r cmd
        [ -z "${cmd}" ] && continue
        run_command_logged "${cmd}"
        ;;
      6)
        printf "path> "
        read -r path
        [ -z "${path}" ] && continue
        if [ -d "${path}" ]; then
          cwd="$(cd "${path}" && pwd -P)"
        else
          echo "Not a directory: ${path}"
        fi
        ;;
      7)
        show_config_status
        ;;
      q|Q) exit 0 ;;
      *) echo "Unknown selection." ;;
    esac
  done
}

check_textual() {
  if ! "${PYTHON_CMD}" -c "import textual" >/dev/null 2>&1; then
    echo "Textual is not installed."
    echo "Install with: ${PYTHON_CMD} -m pip install textual"
    echo ""
    echo "Choose:"
    echo "  A) Run fallback mode"
    echo "  B) Attempt install now"
    printf "Selection [A/B]: "
    read -r choice
    case "${choice:-}" in
      B|b)
        if "${PYTHON_CMD}" -m pip install textual; then
          exec "$0" "$@"
        else
          run_fallback_mode
        fi
        ;;
      *) run_fallback_mode ;;
    esac
  fi
}

run_python_app() {
  OVERWATCH_ACTIVE=1
  disable_mouse_reporting

  local tmp
  if command -v mktemp >/dev/null 2>&1; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/overwatch_XXXXXX.py")"
  else
    tmp="${TMPDIR:-/tmp}/overwatch_$$.py"
  fi

  cat > "${tmp}" <<PY
import asyncio
import json
import os
import platform as _platform
import shlex
import shutil
import string
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple
import urllib.error
import urllib.request

CURRENT_PLATFORM = "${PLATFORM}"

SCRIPT_DIR = Path("${SCRIPT_DIR}").resolve()
COCKPIT_DIR = Path("${COCKPIT_DIR}").resolve()
REPO_ROOT = Path("${REPO_ROOT}").resolve()
RUNS_DIR = Path("${RUNS_DIR}").resolve()
CONFIG_DIR = Path("${CONFIG_DIR}").resolve()
ENV_FILE = Path("${ENV_FILE}").resolve()
LOCKER_DIR = Path("${LOCKER_DIR}").resolve()
AI_LOG_PATH = RUNS_DIR / "ai_output.log"

RUNS_DIR.mkdir(parents=True, exist_ok=True)

TERMUX_VERSION = os.environ.get("TERMUX_VERSION", "")
TERMUX_PATH = os.environ.get("PATH", "")
TERMUX_PREFIX = os.environ.get("PREFIX", "")
IS_TERMUX = bool(TERMUX_VERSION) or "/data/data/com.termux" in TERMUX_PATH or "com.termux" in TERMUX_PREFIX
TERMUX_HIDE_ON_SUBMIT = os.environ.get("OVERWATCH_TERMUX_HIDE_ON_SUBMIT", "").lower() in ("1", "true", "yes", "on")

def termux_keyboard(show: bool) -> None:
    if not IS_TERMUX:
        return
    action = "show" if show else "hide"
    if shutil.which("termux-keyboard"):
        subprocess.Popen(
            ["termux-keyboard", action],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return
    if shutil.which("termux-api"):
        try:
            subprocess.Popen(
                ["termux-api", "Keyboard", action],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            return

def load_env_file(path: Path) -> dict:
    data = {}
    if not path.exists():
        return data
    try:
        lines = path.read_text(errors="ignore").splitlines()
    except Exception:
        return data
    for line in lines:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("export "):
            s = s[len("export "):].strip()
        if "=" not in s:
            continue
        k, v = s.split("=", 1)
        v = v.strip()
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            v = v[1:-1]
        data[k.strip()] = v
    return data

def merge_env_file(path: Path) -> dict:
    env = load_env_file(path)
    for key in ("OPENAI_API_KEY", "OPENAI_MODEL", "OPENAI_BASE_URL"):
        val = os.environ.get(key)
        if val:
            env[key] = val
    return env

def now_utc() -> str:
    return datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

def make_run_dir(mode: str, action: str) -> Path:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    d = RUNS_DIR / f"{ts}_{mode}_{action}"
    d.mkdir(parents=True, exist_ok=True)
    return d

def write_metadata(run_dir: Path, mode: str, action: str, command: str, cwd: Path, exit_code: int, started: str, ended: str) -> None:
    meta = {
        "mode": mode,
        "action": action,
        "command": command,
        "exit_code": int(exit_code),
        "platform": CURRENT_PLATFORM,
        "os": _platform.system(),
        "arch": _platform.machine(),
        "cwd": str(cwd),
        "started_at": started,
        "ended_at": ended,
    }
    try:
        (run_dir / "metadata.json").write_text(json.dumps(meta, indent=2))
    except Exception:
        pass

def is_destructive(cmd: str) -> bool:
    s = cmd.lower()
    bad = ["rm -rf", "rm -fr", "mkfs", "dd ", "shutdown", "reboot", "poweroff", "halt", ":(){:|:&};:"]
    return any(t in s for t in bad)

def tail_text(path: Path, max_chars: int = 9000) -> str:
    try:
        data = path.read_text(errors="ignore")
        return data[-max_chars:]
    except Exception:
        return "(unable to read)"

def sanitize_ai_text(text: str, secret: str = "") -> str:
    safe = "".join(ch for ch in text if ch.isprintable() or ch in "\n\t")
    if secret:
        safe = safe.replace(secret, "[redacted]")
    if "OPENAI_API_KEY" in safe:
        safe = safe.replace("OPENAI_API_KEY", "OPENAI_API_KEY[redacted]")
    return safe

def extract_ai_text(raw: str) -> str:
    try:
        data = json.loads(raw)
    except Exception:
        return raw.strip()
    if isinstance(data, dict):
        if isinstance(data.get("output_text"), str):
            return data["output_text"].strip()
        output = data.get("output")
        if isinstance(output, list):
            chunks = []
            for item in output:
                if not isinstance(item, dict):
                    continue
                content = item.get("content")
                if not isinstance(content, list):
                    continue
                for part in content:
                    if not isinstance(part, dict):
                        continue
                    if part.get("type") in ("output_text", "text") and isinstance(part.get("text"), str):
                        chunks.append(part["text"])
            if chunks:
                return "\n".join(chunks).strip()
    return raw.strip()

def list_dir_entries(cwd: Path) -> Tuple[list, str]:
    try:
        entries = list(cwd.iterdir())
    except Exception as e:
        return [], f"Cannot list directory: {e}"
    dirs = sorted([p for p in entries if p.is_dir()], key=lambda p: p.name.lower())
    files = sorted([p for p in entries if p.is_file()], key=lambda p: p.name.lower())
    return dirs + files, ""

def list_dir_entries_limited(cwd: Path, limit: int = 500) -> Tuple[list, bool, str]:
    try:
        entries = list(cwd.iterdir())
    except Exception as e:
        return [], False, f"Cannot list directory: {e}"
    dirs = sorted([p for p in entries if p.is_dir()], key=lambda p: p.name.lower())
    files = sorted([p for p in entries if p.is_file()], key=lambda p: p.name.lower())
    combined = dirs + files
    has_more = len(combined) > limit
    return combined[:limit], has_more, ""

def truncate_text(text: str, max_len: int) -> str:
    if max_len <= 0:
        return ""
    if len(text) <= max_len:
        return text
    if max_len == 1:
        return "…"
    return text[: max_len - 1] + "…"

def shorten_path(path: Path, max_len: int = 28) -> str:
    s = str(path)
    if len(s) <= max_len:
        return s
    parts = path.parts
    if len(parts) >= 2:
        base = parts[-1]
        root = parts[0]
        compact = f"{root}{os.sep}…{os.sep}{base}"
        if len(compact) <= max_len:
            return compact
    return truncate_text(s, max_len)

from dataclasses import dataclass, field
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Vertical
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widgets import Footer, Input, Label, ListItem, ListView, Static, TextArea
try:
    from textual.widgets import Tree
    TREE_AVAILABLE = True
except Exception:
    Tree = None
    TREE_AVAILABLE = False

# reduce mouse weirdness
os.environ.setdefault("TEXTUAL_NO_MOUSE", "1")

ACCENT = "#f4a259"      # dark orange trim
ACCENT_DIM = "#d9822b"  # darker orange
BG = "#141517"
PANEL = "#16181b"
PANEL2 = "#191b1f"
BORDER = "#2b2f34"
TEXT = "#c7cbd1"
TEXT_DIM = "#9aa3ad"

@dataclass
class FileNode:
    label: str
    path: Optional[Path]
    is_dir: bool
    depth: int = 0
    expanded: bool = False
    loaded: bool = False
    is_placeholder: bool = False
    children: list["FileNode"] = field(default_factory=list)

class ConfirmScreen(ModalScreen[str]):
    def __init__(self, prompt: str):
        super().__init__()
        self.prompt = prompt

    def compose(self) -> ComposeResult:
        yield Label(self.prompt)
        yield Input(placeholder="Type yes to confirm", id="confirm-input")

    def on_mount(self) -> None:
        self.query_one("#confirm-input", Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value.strip())

class StatusHeader(Static):
    mode = reactive("Observe")
    cwd = reactive(str(REPO_ROOT))
    ai = reactive("AI: unavailable")

    def render(self) -> str:
        app = self.app
        app_size = getattr(app, "size", None)
        width = self.size.width or (app_size.width if app_size else 80)
        is_narrow = getattr(app, "is_narrow", False)
        if is_narrow:
            cwd_display = shorten_path(Path(self.cwd), max_len=26)
            base = f"OVERWATCH | AXIOM | {self.mode} | {CURRENT_PLATFORM} | CWD: {cwd_display} | {self.ai}"
        else:
            t = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            base = f"OVERWATCH | AXIOM | {self.mode} | {CURRENT_PLATFORM} | CWD: {self.cwd} | {t} | {self.ai}"
        return truncate_text(base, max(1, width - 1))

class NavItem(ListItem):
    def __init__(self, label: str, tag: str = ""):
        super().__init__(Label(label))
        self.label_text = label
        self.tag = tag or label

class ObservePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Recent Runs")
        yield Input(placeholder="Filter runs...", id="observe-filter")
        yield ListView(id="observe-list")
        yield TextArea(id="observe-output", read_only=True)

class FilesPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Filesystem Navigator")
        yield Label("Enter: expand/collapse | [M] Move | [P] Preview | [R] Refresh", id="files-hint")
        yield Label("CWD:", id="files-cwd")
        yield Input(placeholder="Type a path and press Enter", id="files-path")
        if TREE_AVAILABLE:
            yield Tree("Filesystem", id="files-tree")
        else:
            yield ListView(id="files-tree")
        yield TextArea(id="files-preview", read_only=True)

class OperatePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Locker Tools")
        yield ListView(id="operate-list")
        yield Input(placeholder="Arguments", id="operate-args")
        yield TextArea(id="operate-preview", read_only=True)

class TerminalInfoPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Terminal Operations")
        yield TextArea(
            "Use the terminal pane to run commands.\n"
            "Enter runs in current CWD.\n"
            "CTRL+C cancels the active command.\n",
            read_only=True,
        )

class SignalPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Signal")
        yield TextArea(
            "Telemetry online.\n"
            "No active alerts.\n",
            read_only=True,
        )

class ConfigPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Config Status")
        yield TextArea(id="config-text", read_only=True)

class AboutPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("OVERWATCH | AXIOM")
        yield TextArea(
            "System: AXIOM — Overwatch Cockpit\n"
            "Developer: Justadudeinspace (JADIS)\n"
            "Email: theoutervoid@outlook.com\n"
            "Developer GitHub: https://github.com/Justadudeinspace\n"
            "Repo: https://github.com/Justadudeinspace/axiom\n"
            "\n"
            "Mission: Spaceship-grade terminal cockpit for cross-platform ops (Termux, Debian/WSL, Linux, macOS).\n"
            "\n"
            "Keys: Enter expand/collapse or preview | M move CWD | P preview | R refresh\n"
            "Keys: / search | Tab cycle panes | T toggle terminal (narrow) | Q quit\n",
            read_only=True,
        )

class TerminalPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Terminal", id="term-title")
        yield Label("", id="term-cwd")
        yield Input(placeholder="Command (Enter runs)", id="term-cmd")
        yield TextArea(id="term-output", read_only=True)

class OverwatchApp(App):
    CSS = f"""
    Screen {{
        background: {BG};
        color: {TEXT};
    }}
    #root {{
        height: 100%;
    }}
    #header {{
        background: #1b1d20;
        color: {TEXT};
        padding: 1 2;
        border: solid {BORDER};
        overflow-x: hidden;
    }}
    #ai-window {{
        dock: top;
        height: 6;
        border: solid {ACCENT_DIM};
        background: #101214;
        color: {TEXT};
        padding: 0 1;
    }}
    #ai-window:focus {{
        border: solid {ACCENT};
    }}
    #body {{
        height: 1fr;
        layout: horizontal;
        overflow-x: hidden;
    }}
    #left {{
        width: 1fr;
        min-width: 28;
        border: solid {BORDER};
        background: {PANEL};
        overflow-x: hidden;
    }}
    #right {{
        width: 40;
        min-width: 30;
        max-width: 50%;
        border: solid {BORDER};
        background: {PANEL};
        overflow-x: hidden;
    }}
    #body.narrow {{
        layout: vertical;
    }}
    #left.narrow {{
        min-width: 20;
    }}
    #right.narrow {{
        width: 1fr;
        height: 12;
        min-height: 12;
        max-width: 100%;
    }}
    #nav {{
        background: {PANEL2};
        border: solid {BORDER};
        height: 10;
    }}
    #main {{
        border-top: solid {BORDER};
        background: {PANEL};
        padding: 1 1;
        height: 1fr;
        overflow-x: hidden;
    }}
    #footer {{
        background: #1b1d20;
        color: {TEXT_DIM};
        border: solid {BORDER};
    }}
    ListView > .list-item--highlight {{
        background: #2a1a0a;
        color: {ACCENT};
    }}
    ListView:focus {{
        border: solid {ACCENT_DIM};
    }}
    Input:focus, TextArea:focus {{
        border: solid {ACCENT};
    }}
    #files-hint {{
        color: {ACCENT_DIM};
    }}
    #files-tree {{
        border: solid {BORDER};
        height: 1fr;
    }}
    #files-preview {{
        border: solid {BORDER};
    }}
    Tree:focus {{
        border: solid {ACCENT_DIM};
    }}
    #observe-filter {{
        border: solid {BORDER};
        background: #111214;
    }}
    #observe-list {{
        border: solid {BORDER};
    }}
    #observe-output {{
        border: solid {BORDER};
    }}
    #term-title {{
        color: {ACCENT};
    }}
    #term-cwd {{
        color: {ACCENT_DIM};
    }}
    #operate-preview {{
        border: solid {BORDER};
    }}
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("escape", "back", "Back"),
        Binding("tab", "focus_next", "Next Pane"),
        Binding("/", "search", "Search"),
        Binding("t", "toggle_terminal", "Terminal"),
        Binding("enter", "enter", "Enter"),
        Binding("m", "move_cwd", "Move"),
        Binding("p", "preview", "Preview"),
        Binding("backspace", "collapse_node", "Collapse"),
        Binding("r", "refresh", "Refresh"),
        Binding("a", "ai_ping", "AI Ping"),
        Binding("?", "help", "Help"),
        Binding("ctrl+c", "cancel", "Cancel"),
        Binding("k", "toggle_keyboard", "Keyboard"),
    ]

    mode = reactive("Observe")
    is_narrow = reactive(False)
    terminal_visible = reactive(True)
    keyboard_visible = reactive(False)
    cwd = reactive(REPO_ROOT)

    def __init__(self):
        super().__init__()
        self._running_proc: Optional[asyncio.subprocess.Process] = None
        self._running_task: Optional[asyncio.Task] = None
        self.nav_map = ["Observe", "Files", "Operate", "Terminal", "Signal", "Config", "About"]
        self._observe_filter = ""
        self._locker_desc = {}
        self._files_fallback_roots: list["FileNode"] = []
        self._files_fallback_visible: list["FileNode"] = []
        self._ai_buffer = ""
        self._ai_log_path = AI_LOG_PATH
        self._ai_max_chars = 4000
        self._ai_unavailable_emitted = False
        self._ai_model = ""
        self._ai_base_url = "https://api.openai.com/v1"

    def compose(self) -> ComposeResult:
        with Vertical(id="root"):
            yield StatusHeader(id="header")
            yield TextArea(id="ai-window", read_only=True)
            with Container(id="body"):
                with Vertical(id="left"):
                    yield ListView(id="nav")
                    with Container(id="main"):
                        self.observe = ObservePane(id="observe-pane")
                        self.files = FilesPane(id="files-pane")
                        self.operate = OperatePane(id="operate-pane")
                        self.terminal = TerminalInfoPane(id="terminal-pane")
                        self.signal = SignalPane(id="signal-pane")
                        self.config = ConfigPane(id="config-pane")
                        self.about = AboutPane(id="about-pane")
                        yield self.observe
                        yield self.files
                        yield self.operate
                        yield self.terminal
                        yield self.signal
                        yield self.config
                        yield self.about
                yield TerminalPane(id="right")
            yield Footer(id="footer")

    def on_mount(self) -> None:
        nav = self.query_one("#nav", ListView)
        nav.clear()
        for name in self.nav_map:
            nav.append(NavItem(name))
        nav.index = 0
        self.update_ai_status()
        self.initialize_ai_window()
        self.update_cwd_labels()
        self.switch_mode("Observe")
        self.refresh_all()
        nav.focus()
        self._locker_desc = self.load_locker_descriptions()
        self.set_responsive_state(self.size.width)
        self.update_terminal_help()

    def update_terminal_help(self) -> None:
        info = self.query_one("#terminal-pane", TerminalInfoPane)
        lines = [
            "Use the terminal pane to run commands.",
            "Enter runs in current CWD.",
            "CTRL+C cancels the active command.",
            "Esc returns focus to nav.",
            "Files: Enter expand/collapse | M move CWD | P preview.",
        ]
        if IS_TERMUX:
            lines.append("k toggles keyboard (Termux).")
        info.query_one(TextArea).text = "\n".join(lines) + "\n"

    def on_resize(self, event) -> None:
        self.set_responsive_state(event.size.width)
        self.query_one(StatusHeader).refresh()

    def set_responsive_state(self, width: int) -> None:
        self.is_narrow = width < 120
        self.update_layout()

    def update_layout(self) -> None:
        body = self.query_one("#body", Container)
        right = self.query_one("#right", TerminalPane)
        left = self.query_one("#left", Vertical)
        if self.is_narrow:
            body.add_class("narrow")
            right.add_class("narrow")
            left.add_class("narrow")
        else:
            body.remove_class("narrow")
            right.remove_class("narrow")
            left.remove_class("narrow")
        right.display = (not self.is_narrow) or self.terminal_visible
        if right.display:
            right.refresh()

    def update_ai_status(self) -> None:
        env = merge_env_file(ENV_FILE)
        key_ok = bool(env.get("OPENAI_API_KEY", "").strip())
        model = env.get("OPENAI_MODEL", "").strip()
        hdr = self.query_one(StatusHeader)
        hdr.ai = f"AI: {model}" if (key_ok and model) else "AI: unavailable"
        if key_ok and model:
            self._ai_model = model
        base_url = env.get("OPENAI_BASE_URL", "").strip()
        if base_url:
            self._ai_base_url = base_url

    def update_cwd_labels(self) -> None:
        hdr = self.query_one(StatusHeader)
        hdr.cwd = str(self.cwd)
        self.query_one("#files-cwd", Label).update(f"CWD: {self.cwd}")
        self.query_one("#term-cwd", Label).update(f"CWD: {self.cwd}")

    def switch_mode(self, name: str) -> None:
        self.mode = name
        hdr = self.query_one(StatusHeader)
        hdr.mode = name
        self.observe.display = (name == "Observe")
        self.files.display = (name == "Files")
        self.operate.display = (name == "Operate")
        self.terminal.display = (name == "Terminal")
        self.signal.display = (name == "Signal")
        self.config.display = (name == "Config")
        self.about.display = (name == "About")
        if name == "Terminal":
            self.focus_terminal_input()

    def action_back(self) -> None:
        self.query_one("#nav", ListView).focus()

    def action_search(self) -> None:
        if self.mode == "Files":
            self.query_one("#files-path", Input).focus()
        elif self.mode == "Observe":
            self.query_one("#observe-filter", Input).focus()

    def action_toggle_terminal(self) -> None:
        if self.is_narrow:
            self.terminal_visible = not self.terminal_visible
            self.update_layout()
        if not self.is_narrow or self.terminal_visible:
            self.focus_terminal_input()

    def action_toggle_keyboard(self) -> None:
        if not IS_TERMUX:
            return
        if self.mode != "Terminal" and not self.terminal_visible:
            return
        self.set_keyboard_visible(not self.keyboard_visible)

    def focus_terminal_input(self) -> None:
        term_input = self.query_one("#term-cmd", Input)
        term_input.focus()
        self.set_keyboard_visible(True)

    def set_keyboard_visible(self, show: bool) -> None:
        if not IS_TERMUX:
            self.keyboard_visible = False
            return
        self.keyboard_visible = show
        termux_keyboard(show)

    def action_refresh(self) -> None:
        self.refresh_all()

    def refresh_all(self) -> None:
        self.refresh_observe()
        self.refresh_files()
        self.refresh_operate()
        self.refresh_config()
        self.update_ai_status()
        self.update_cwd_labels()

    def refresh_observe(self) -> None:
        lv = self.query_one("#observe-list", ListView)
        lv.clear()
        runs = [p for p in RUNS_DIR.iterdir()] if RUNS_DIR.exists() else []
        runs = [p for p in runs if p.is_dir()]
        runs = sorted(runs, key=lambda p: p.name, reverse=True)
        out = self.query_one("#observe-output", TextArea)
        if self._observe_filter:
            runs = [p for p in runs if self._observe_filter in p.name.lower()]
        if not runs:
            lv.append(NavItem("No runs yet.", tag="__empty__"))
            out.text = "No runs yet.\n"
            return
        for r in runs[:80]:
            lv.append(NavItem(r.name))
        lv.index = 0
        self.open_selected_run()

    def open_selected_run(self) -> None:
        lv = self.query_one("#observe-list", ListView)
        if lv.index is None:
            return
        item = lv.get_item_at(lv.index)
        if not isinstance(item, NavItem) or item.tag == "__empty__":
            return
        run_dir = RUNS_DIR / item.label_text
        out = run_dir / "output.log"
        meta = run_dir / "metadata.json"
        chunks = []
        if meta.exists():
            try:
                chunks.append(meta.read_text(errors="ignore")[:2000])
                chunks.append("\n---\n")
            except Exception:
                pass
        chunks.append(tail_text(out) if out.exists() else "No output.log found.")
        self.query_one("#observe-output", TextArea).text = "".join(chunks)

    def refresh_files(self) -> None:
        preview = self.query_one("#files-preview", TextArea)
        preview.text = "Select an entry and press Enter.\n"
        if TREE_AVAILABLE:
            tree = self.query_one("#files-tree", Tree)
            self.build_files_tree(tree)
        else:
            self.build_files_tree_fallback()

    def get_files_root_paths(self) -> list[Path]:
        if os.name == "nt":
            drives = []
            for letter in string.ascii_uppercase:
                drive = Path(f"{letter}:/")
                if drive.exists():
                    drives.append(drive)
            return drives or [Path("/")]
        return [Path(os.sep)]

    def reset_tree_node(self, node, label: str) -> None:
        if hasattr(node, "clear"):
            node.clear()
        elif hasattr(node, "remove_children"):
            node.remove_children()
        else:
            try:
                node.children.clear()
            except Exception:
                pass
        if hasattr(node, "set_label"):
            node.set_label(label)
        else:
            node.label = label

    def build_files_tree(self, tree) -> None:
        root_paths = self.get_files_root_paths()
        root = tree.root
        if len(root_paths) == 1:
            root_path = root_paths[0]
            self.reset_tree_node(root, str(root_path))
            root.data = {"path": str(root_path), "is_dir": True, "loaded": False}
            root.allow_expand = True
            self.populate_tree_node(root)
        else:
            self.reset_tree_node(root, "Computer")
            root.data = {"path": None, "is_dir": True, "loaded": True}
            for drive in root_paths:
                child = root.add(str(drive), data={"path": str(drive), "is_dir": True, "loaded": False})
                child.allow_expand = True
        root.expand()

    def populate_tree_node(self, node) -> None:
        data = node.data or {}
        if data.get("loaded") or not data.get("is_dir"):
            return
        path_str = data.get("path")
        if not path_str:
            return
        path = Path(path_str)
        entries, has_more, err = list_dir_entries_limited(path)
        if err:
            node.add("[permission denied]", data={"path": None, "is_dir": False, "error": err})
            data["loaded"] = True
            node.data = data
            return
        for entry in entries:
            if entry.is_dir():
                child = node.add(f"{entry.name}/", data={"path": str(entry), "is_dir": True, "loaded": False})
                child.allow_expand = True
            else:
                node.add(entry.name, data={"path": str(entry), "is_dir": False})
        if has_more:
            node.add("(more...)", data={"path": None, "is_dir": False, "more": True})
        data["loaded"] = True
        node.data = data

    def handle_tree_selection(self, node, expand_toggle: bool) -> None:
        preview = self.query_one("#files-preview", TextArea)
        data = node.data or {}
        if data.get("more"):
            preview.text = "More entries exist in this directory.\n"
            return
        path_str = data.get("path")
        if not path_str:
            if data.get("error"):
                preview.text = f"{data.get('error')}\n"
            return
        path = Path(path_str)
        if data.get("is_dir"):
            if expand_toggle:
                if node.is_expanded:
                    node.collapse()
                else:
                    self.populate_tree_node(node)
                    node.expand()
            preview.text = self.preview_path(path)
        else:
            preview.text = self.preview_path(path)

    def build_files_tree_fallback(self) -> None:
        roots = self.get_files_root_paths()
        self._files_fallback_roots = []
        if len(roots) == 1:
            root_path = roots[0]
            self._files_fallback_roots.append(
                FileNode(label=str(root_path), path=root_path, is_dir=True, depth=0)
            )
        else:
            for drive in roots:
                self._files_fallback_roots.append(
                    FileNode(label=str(drive), path=drive, is_dir=True, depth=0)
                )
        self.rebuild_fallback_visible()
        self.render_fallback_list()

    def load_fallback_children(self, node: FileNode) -> None:
        if node.loaded or not node.path or not node.is_dir:
            return
        entries, has_more, err = list_dir_entries_limited(node.path)
        if err:
            node.children.append(
                FileNode(label="[permission denied]", path=None, is_dir=False, depth=node.depth + 1, is_placeholder=True)
            )
            node.loaded = True
            return
        for entry in entries:
            node.children.append(
                FileNode(
                    label=f"{entry.name}/" if entry.is_dir() else entry.name,
                    path=entry,
                    is_dir=entry.is_dir(),
                    depth=node.depth + 1,
                )
            )
        if has_more:
            node.children.append(
                FileNode(label="(more...)", path=None, is_dir=False, depth=node.depth + 1, is_placeholder=True)
            )
        node.loaded = True

    def rebuild_fallback_visible(self) -> None:
        visible: list[FileNode] = []

        def walk(nodes: list[FileNode]) -> None:
            for n in nodes:
                visible.append(n)
                if n.is_dir and n.expanded:
                    walk(n.children)

        walk(self._files_fallback_roots)
        self._files_fallback_visible = visible

    def format_fallback_label(self, node: FileNode) -> str:
        indent = "  " * node.depth
        if node.is_placeholder:
            return f"{indent}{node.label}"
        if node.is_dir:
            marker = "v" if node.expanded else ">"
            return f"{indent}{marker} {node.label}"
        return f"{indent}  {node.label}"

    def render_fallback_list(self) -> None:
        lv = self.query_one("#files-tree", ListView)
        lv.clear()
        for node in self._files_fallback_visible:
            lv.append(NavItem(self.format_fallback_label(node)))
        if lv.index is None and self._files_fallback_visible:
            lv.index = 0

    def handle_fallback_selection(self, expand_toggle: bool) -> None:
        lv = self.query_one("#files-tree", ListView)
        if lv.index is None or lv.index >= len(self._files_fallback_visible):
            return
        node = self._files_fallback_visible[lv.index]
        preview = self.query_one("#files-preview", TextArea)
        if node.is_placeholder or node.path is None:
            if node.label == "(more...)":
                preview.text = "More entries exist in this directory.\n"
            else:
                preview.text = "Unable to access this entry.\n"
            return
        if node.is_dir:
            if expand_toggle:
                if node.expanded:
                    node.expanded = False
                else:
                    self.load_fallback_children(node)
                    node.expanded = True
                self.rebuild_fallback_visible()
                self.render_fallback_list()
                lv.index = min(lv.index, len(self._files_fallback_visible) - 1)
            preview.text = self.preview_path(node.path)
        else:
            preview.text = self.preview_path(node.path)

    def get_selected_files_path(self) -> Optional[Path]:
        if TREE_AVAILABLE:
            tree = self.query_one("#files-tree", Tree)
            node = tree.cursor_node
            if node is None:
                return None
            data = node.data or {}
            path_str = data.get("path")
            if not path_str:
                return None
            return Path(path_str)
        lv = self.query_one("#files-tree", ListView)
        if lv.index is None or lv.index >= len(self._files_fallback_visible):
            return None
        node = self._files_fallback_visible[lv.index]
        return node.path

    def preview_path(self, p: Path) -> str:
        try:
            st = p.stat()
        except Exception as e:
            return f"Cannot stat: {e}"
        mtime = datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        if p.is_dir():
            try:
                count = sum(1 for _ in p.iterdir())
            except Exception:
                count = -1
            return f"DIR: {p}\nModified: {mtime}\nItems: {count}\n"
        size = st.st_size
        head = f"FILE: {p}\nModified: {mtime}\nSize: {size} bytes\n\n"
        try:
            max_bytes = 20000
            data = p.read_bytes()[:max_bytes]
            if b"\x00" in data:
                return head + "(binary file preview skipped)\n"
            content = data.decode(errors="ignore")
            suffix = "\n\n...[truncated]...\n" if size > max_bytes else ""
            return head + content + suffix
        except Exception as e:
            return head + f"(unable to read file: {e})\n"

    def refresh_operate(self) -> None:
        lv = self.query_one("#operate-list", ListView)
        lv.clear()
        preview = self.query_one("#operate-preview", TextArea)
        if not LOCKER_DIR.exists():
            lv.append(NavItem("No locker directory.", tag="__empty__"))
            preview.text = f"LOCKER_DIR not found: {LOCKER_DIR}\n"
            return
        tools = sorted([p for p in LOCKER_DIR.glob("*.sh") if p.is_file()], key=lambda p: p.name.lower())
        if not tools:
            lv.append(NavItem("No tools found.", tag="__empty__"))
            preview.text = "No *.sh tools found in locker.\n"
            return
        for t in tools:
            lv.append(NavItem(t.name, tag=str(t)))
        lv.index = 0
        preview.text = "Select a tool, add args, press Enter to run (with confirmation).\n"

    def refresh_config(self) -> None:
        env_path = ENV_FILE
        if not env_path.exists() and (CONFIG_DIR / ".env.example").exists():
            env_path = CONFIG_DIR / ".env.example"
        env = merge_env_file(env_path)
        lines = [f"Config file: {env_path}\n"]
        lines.append(f"OPENAI_API_KEY: {'set' if env.get('OPENAI_API_KEY') else 'not set'}\n")
        lines.append(f"OPENAI_MODEL: {env.get('OPENAI_MODEL','not set') or 'not set'}\n")
        self.query_one("#config-text", TextArea).text = "".join(lines)

    def initialize_ai_window(self) -> None:
        env = merge_env_file(ENV_FILE)
        key = env.get("OPENAI_API_KEY", "").strip()
        model = env.get("OPENAI_MODEL", "").strip()
        if key and model:
            self.ai_emit("startup", f"AI online: model={model}", status="ok", model=model)
        else:
            self.ai_emit("startup", "AI unavailable: missing OPENAI_API_KEY or OPENAI_MODEL", status="error")
            self._ai_unavailable_emitted = True

    def ai_emit(self, action: str, text: str, status: str = "ok", model: str = "") -> None:
        env = merge_env_file(ENV_FILE)
        secret = env.get("OPENAI_API_KEY", "").strip()
        safe_text = sanitize_ai_text(text, secret=secret)
        model_name = model or env.get("OPENAI_MODEL", "").strip() or self._ai_model or "unknown"
        timestamp = now_utc()
        header = f"[{timestamp}] model={model_name} action={action} status={status}"
        entry = f"{header}\n{safe_text}\n"
        self._ai_buffer = (self._ai_buffer + entry)[-self._ai_max_chars :]
        ai_window = self.query_one("#ai-window", TextArea)
        ai_window.text = self._ai_buffer
        ai_window.scroll_end(animate=False)
        try:
            self._ai_log_path.parent.mkdir(parents=True, exist_ok=True)
            with self._ai_log_path.open("a", encoding="utf-8", errors="ignore") as f:
                f.write(f"{header}\n{safe_text}\n--- end ---\n")
        except Exception:
            pass

    def ai_error(self, action: str, err: str) -> None:
        self.ai_emit(action, err, status="error")

    async def action_ai_ping(self) -> None:
        asyncio.create_task(self.run_ai_ping())

    async def run_ai_ping(self) -> None:
        action = "ai_ping"
        env = merge_env_file(ENV_FILE)
        key = env.get("OPENAI_API_KEY", "").strip()
        model = env.get("OPENAI_MODEL", "").strip()
        base_url = env.get("OPENAI_BASE_URL", "").strip() or self._ai_base_url
        if not key or not model:
            msg = "AI unavailable: missing OPENAI_API_KEY or OPENAI_MODEL"
            self.ai_emit(action, msg, status="error")
            return
        self._ai_model = model
        self._ai_base_url = base_url.rstrip("/")
        self.ai_emit(action, "Requesting analysis...", status="info", model=model)

        run_dir = make_run_dir("ai", "ping")
        out_path = run_dir / "output.log"
        started = now_utc()
        exit_code = 1
        response_text = ""

        def do_request() -> str:
            payload = {"model": model, "input": "Say ok"}
            data = json.dumps(payload).encode("utf-8")
            url = f"{self._ai_base_url}/responses"
            req = urllib.request.Request(
                url,
                data=data,
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read().decode("utf-8", errors="ignore")

        try:
            raw = await asyncio.to_thread(do_request)
            response_text = extract_ai_text(raw) or raw
            self.ai_emit(action, response_text, status="ok", model=model)
            exit_code = 0
        except Exception as e:
            err = f"AI call failed: {e}"
            self.ai_error(action, err)
            response_text = err
            exit_code = 1
        finally:
            try:
                out_path.write_text(response_text, encoding="utf-8", errors="ignore")
            except Exception:
                pass
            write_metadata(run_dir, "ai", "ping", "openai.responses", self.cwd, exit_code, started, now_utc())

    def load_locker_descriptions(self) -> dict:
        desc = {}
        readme = LOCKER_DIR / "README.md"
        if not readme.exists():
            return desc
        try:
            for line in readme.read_text(errors="ignore").splitlines():
                if ":" in line and ".sh" in line:
                    parts = line.split(":", 1)
                    name = parts[0].strip().lstrip("-* ").strip()
                    if name.endswith(".sh"):
                        desc[name] = parts[1].strip()
        except Exception:
            return desc
        return desc

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id == "nav":
            item = event.item
            if isinstance(item, NavItem):
                self.switch_mode(item.label_text)
                self.update_cwd_labels()
        elif event.list_view.id == "observe-list":
            self.open_selected_run()
        elif event.list_view.id == "files-tree" and not TREE_AVAILABLE:
            self.handle_fallback_selection(expand_toggle=True)
        elif event.list_view.id == "operate-list":
            item = event.item
            if not isinstance(item, NavItem) or item.tag == "__empty__":
                return
            tool = Path(item.tag)
            args = self.query_one("#operate-args", Input).value.strip()
            cmd = f"{tool} {args}".strip()
            desc = self._locker_desc.get(tool.name, "")
            extra = f"\nDesc: {desc}\n" if desc else "\n"
            self.query_one("#operate-preview", TextArea).text = f"CWD: {self.cwd}\nPreview: {cmd}{extra}"

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "files-path":
            raw = event.value.strip()
            if not raw:
                return
            p = Path(raw).expanduser()
            try:
                p = p.resolve()
            except Exception:
                pass
            if p.exists() and p.is_dir():
                self.cwd = p
                self.update_cwd_labels()
                self.refresh_files()
                self.query_one("#files-tree").focus()
            else:
                self.query_one("#files-preview", TextArea).text = f"Invalid directory: {raw}\n"
        elif event.input.id == "term-cmd":
            cmd = event.value.strip()
            if not cmd:
                return
            event.input.value = ""
            asyncio.create_task(self.run_terminal_command(cmd))
            if TERMUX_HIDE_ON_SUBMIT:
                self.set_keyboard_visible(False)
        elif event.input.id == "observe-filter":
            self._observe_filter = event.value.strip().lower()
            self.refresh_observe()

    def on_descendant_focus(self, event) -> None:
        control = getattr(event, "control", None)
        if getattr(control, "id", None) == "term-cmd":
            self.set_keyboard_visible(True)

    def on_descendant_blur(self, event) -> None:
        control = getattr(event, "control", None)
        if getattr(control, "id", None) == "term-cmd":
            self.set_keyboard_visible(False)

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "observe-filter":
            self._observe_filter = event.value.strip().lower()
            self.refresh_observe()

    async def action_enter(self) -> None:
        focused = self.focused
        if self.mode == "Files" and focused is not None and focused.id == "files-tree":
            await self.files_enter()
        elif self.mode == "Operate" and isinstance(focused, ListView) and focused.id == "operate-list":
            await self.operate_enter()
        elif self.mode == "Observe" and isinstance(focused, ListView) and focused.id == "observe-list":
            self.open_selected_run()

    async def files_enter(self) -> None:
        if TREE_AVAILABLE:
            tree = self.query_one("#files-tree", Tree)
            node = tree.cursor_node
            if node is None:
                return
            self.handle_tree_selection(node, expand_toggle=True)
        else:
            self.handle_fallback_selection(expand_toggle=True)

    async def operate_enter(self) -> None:
        lv = self.query_one("#operate-list", ListView)
        if lv.index is None:
            return
        item = lv.get_item_at(lv.index)
        if not isinstance(item, NavItem) or item.tag == "__empty__":
            return
        tool = Path(item.tag)
        args = self.query_one("#operate-args", Input).value.strip()
        cmd = f"{tool} {args}".strip()
        confirm = await self.push_screen(ConfirmScreen(f"Run tool in CWD={self.cwd}?\n{cmd}\nType yes to confirm:"))
        if confirm != "yes":
            self.append_terminal(f"[cancelled] {cmd}\n")
            return
        await self.run_and_stream(mode="operate", action=tool.stem, command=cmd, cwd=self.cwd)

    async def run_terminal_command(self, cmd: str) -> None:
        if is_destructive(cmd):
            confirm = await self.push_screen(ConfirmScreen(f"Destructive command detected:\n{cmd}\nType yes to run:"))
            if confirm != "yes":
                self.append_terminal(f"[blocked] {cmd}\n")
                return
        await self.run_and_stream(mode="terminal", action="shell", command=cmd, cwd=self.cwd)

    def append_terminal(self, text: str) -> None:
        out = self.query_one("#term-output", TextArea)
        out.text += text
        out.scroll_end(animate=False)

    async def run_and_stream(self, mode: str, action: str, command: str, cwd: Path) -> None:
        if self._running_task and not self._running_task.done():
            self.append_terminal("[busy] A process is already running.\n")
            return

        run_dir = make_run_dir(mode, action)
        out_path = run_dir / "output.log"
        started = now_utc()

        self.append_terminal(f"\n> ({cwd}) $ {command}\n")

        # Attempt to preserve scripts that need bash -lc
        shell_cmd = command
        try:
            parts = shlex.split(command)
        except Exception:
            parts = [command]
        if parts:
            first = Path(parts[0])
            if first.exists() and first.is_file() and not os.access(str(first), os.X_OK):
                shell_cmd = f"bash -lc {shlex.quote(command)}"

        async def runner():
            exit_code = 1
            try:
                proc = await asyncio.create_subprocess_shell(
                    shell_cmd,
                    cwd=str(cwd),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                )
                self._running_proc = proc
                with out_path.open("w", encoding="utf-8", errors="ignore") as f:
                    assert proc.stdout is not None
                    while True:
                        line = await proc.stdout.readline()
                        if not line:
                            break
                        text = line.decode(errors="ignore")
                        f.write(text)
                        f.flush()
                        self.append_terminal(text)
                    exit_code = await proc.wait()
            except Exception as e:
                msg = f"[error] {e}\n"
                try:
                    out_path.write_text(msg)
                except Exception:
                    pass
                self.append_terminal(msg)
                exit_code = 1
            finally:
                ended = now_utc()
                write_metadata(run_dir, mode, action, command, cwd, exit_code, started, ended)
                self._running_proc = None
                self._running_task = None
                self.refresh_observe()

        self._running_task = asyncio.create_task(runner())

    def on_tree_node_selected(self, event) -> None:
        if not TREE_AVAILABLE:
            return
        tree = event.tree
        if tree.id != "files-tree":
            return
        self.handle_tree_selection(event.node, expand_toggle=True)

    def on_tree_node_expanded(self, event) -> None:
        if not TREE_AVAILABLE:
            return
        tree = event.tree
        if tree.id != "files-tree":
            return
        self.populate_tree_node(event.node)

    def action_preview(self) -> None:
        if self.mode != "Files":
            return
        if TREE_AVAILABLE:
            tree = self.query_one("#files-tree", Tree)
            node = tree.cursor_node
            if node is None:
                return
            self.handle_tree_selection(node, expand_toggle=False)
        else:
            self.handle_fallback_selection(expand_toggle=False)

    def action_collapse_node(self) -> None:
        if self.mode != "Files":
            return
        if not TREE_AVAILABLE:
            lv = self.query_one("#files-tree", ListView)
            if lv.index is None or lv.index >= len(self._files_fallback_visible):
                return
            node = self._files_fallback_visible[lv.index]
            if node.is_dir and node.expanded:
                node.expanded = False
                self.rebuild_fallback_visible()
                self.render_fallback_list()
            return
        tree = self.query_one("#files-tree", Tree)
        node = tree.cursor_node
        if node is None:
            return
        if node.is_expanded:
            node.collapse()
        elif node.parent is not None:
            node.parent.collapse()

    def action_move_cwd(self) -> None:
        if self.mode != "Files":
            return
        target = self.get_selected_files_path()
        if target is None:
            self.query_one("#files-hint", Label).update("No directory selected for MOVE.")
            return
        if not target.is_dir():
            self.query_one("#files-hint", Label).update("MOVE requires a directory selection.")
            return
        self.cwd = target
        self.update_cwd_labels()
        self.query_one("#files-hint", Label).update(f"CWD set to {self.cwd}")
        self.query_one("#files-preview", TextArea).text = f"CWD set to {self.cwd}\n"

    async def action_cancel(self) -> None:
        if self._running_proc and self._running_task and not self._running_task.done():
            try:
                self._running_proc.terminate()
                self.append_terminal("[cancel] terminated running process.\n")
            except Exception:
                self.append_terminal("[cancel] unable to terminate.\n")

    async def action_quit(self) -> None:
        if self._running_proc and self._running_task and not self._running_task.done():
            confirm = await self.push_screen(ConfirmScreen("A process is running. Quit and terminate it? Type yes:"))
            if confirm != "yes":
                return
            try:
                self._running_proc.terminate()
            except Exception:
                pass
        await super().action_quit()

app = OverwatchApp()
app.run()
PY
  "${PYTHON_CMD}" "${tmp}"
  rm -f "${tmp}" 2>/dev/null || true
}

main() {
  case "${1:-}" in
    --help|-h)
      usage
      exit 0
      ;;
    --self-test)
      check_python
      self_test
      exit 0
      ;;
  esac
  check_python
  check_textual
  echo "Starting Overwatch (Platform: ${PLATFORM})..."
  run_python_app
}

main "$@"
