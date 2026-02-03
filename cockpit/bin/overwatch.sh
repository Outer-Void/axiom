#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
COCKPIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${COCKPIT_DIR}/.." && pwd -P)"

if command -v realpath >/dev/null 2>&1; then
  SCRIPT_DIR="$(realpath "${SCRIPT_DIR}")"
  COCKPIT_DIR="$(realpath "${COCKPIT_DIR}")"
  REPO_ROOT="$(realpath "${REPO_ROOT}")"
fi

RUNS_DIR="${COCKPIT_DIR}/runs"
CONFIG_DIR="${COCKPIT_DIR}/config"
ENV_FILE="${CONFIG_DIR}/.env"
LOCKER_DIR="${REPO_ROOT}/locker"

mkdir -p "${RUNS_DIR}" 2>/dev/null || true

disable_mouse_reporting() {
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1015l\e[?25h'
}

restore_terminal() {
  disable_mouse_reporting
  stty sane 2>/dev/null || true
}

is_termux() {
  [ -n "${TERMUX_VERSION-}" ] || [ -d "/data/data/com.termux" ] || [[ "${PREFIX-}" == *com.termux* ]]
}

TEMP_PY_FILE=""

cleanup_temp() {
  if [ -n "${TEMP_PY_FILE}" ] && [ -f "${TEMP_PY_FILE}" ]; then
    rm -f "${TEMP_PY_FILE}"
  fi
}

trap 'cleanup_temp; restore_terminal' EXIT INT TERM

if ! command -v python3 >/dev/null 2>&1; then
  echo "Overwatch requires python3 but it was not found in PATH." >&2
  echo "Install python3 and rerun: https://www.python.org/downloads/" >&2
  exit 1
fi

if ! python3 -c "import textual" >/dev/null 2>&1; then
  echo "Textual is not installed." >&2
  echo "Choose an option:" >&2
  echo "  A) Run minimal fallback mode" >&2
  echo "  B) Install textual and rerun" >&2
  printf "Selection [A/B]: " >&2
  read -r choice
  case "${choice:-}" in
    A|a)
      :
      ;;
    *)
      echo "Install with: python3 -m pip install textual" >&2
      exit 1
      ;;
  esac

  safe_mkdir() {
    mkdir -p "$1" 2>/dev/null || true
  }

  write_metadata() {
    local run_dir="$1"
    local mode="$2"
    local action="$3"
    local command="$4"
    local exit_code="$5"
    local started="$6"
    local ended="$7"
    local cwd="$8"
    cat >"${run_dir}/metadata.json" <<META
{
  "mode": "${mode}",
  "action": "${action}",
  "command": "${command}",
  "exit_code": ${exit_code},
  "platform": "$(uname -s 2>/dev/null || echo unknown)",
  "cwd": "${cwd}",
  "started_at": "${started}",
  "ended_at": "${ended}"
}
META
  }

  run_command() {
    local mode="$1"
    local action="$2"
    local cmd="$3"
    safe_mkdir "${RUNS_DIR}"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local run_dir="${RUNS_DIR}/${ts}_${mode}_${action}"
    safe_mkdir "${run_dir}"
    local started
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Running: ${cmd}"
    local exit_code
    local exit_code_file="${run_dir}/.exit_code"
    (
      set +e
      cd "${REPO_ROOT}" || exit 1
      bash -lc "${cmd}"
      echo $? >"${exit_code_file}"
    ) >"${run_dir}/output.log" 2>&1
    if [ -f "${exit_code_file}" ]; then
      exit_code="$(cat "${exit_code_file}")"
      rm -f "${exit_code_file}"
    else
      exit_code=1
    fi
    local ended
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    write_metadata "${run_dir}" "${mode}" "${action}" "${cmd}" "${exit_code}" "${started}" "${ended}" "${REPO_ROOT}"
    echo "Output saved to ${run_dir}/output.log"
    return ${exit_code}
  }

  while true; do
    echo ""
    echo "OVERWATCH: SENTINEL / NIGHT OPS (Fallback Mode)"
    echo "1) Observe runs"
    echo "2) Operate locker tool"
    echo "3) Signal health"
    echo "4) Config status"
    echo "5) About"
    echo "q) Quit"
    printf "> "
    read -r sel
    case "${sel:-}" in
      1)
        ls -1 "${RUNS_DIR}" 2>/dev/null | tail -n 20
        ;;
      2)
        if [ ! -d "${LOCKER_DIR}" ]; then
          echo "Locker directory not found."
          continue
        fi
        echo "Available tools:"
        found_tool=false
        for tool_path in "${LOCKER_DIR}"/*.sh; do
          if [ -e "${tool_path}" ] && [ -x "${tool_path}" ]; then
            found_tool=true
            echo "$(basename "${tool_path}")"
          fi
        done
        if [ "${found_tool}" = false ]; then
          echo "No executable tools found."
        fi
        printf "Tool name: "
        read -r tool
        if [ -z "${tool}" ] || [ ! -f "${LOCKER_DIR}/${tool}" ]; then
          echo "Tool not found."
          continue
        fi
        if [ ! -x "${LOCKER_DIR}/${tool}" ]; then
          echo "Tool is not executable."
          continue
        fi
        printf "Arguments (optional): "
        read -r args
        echo "Confirm run? (yes/no)"
        read -r confirm
        if [ "${confirm}" != "yes" ]; then
          echo "Cancelled."
          continue
        fi
        run_command "operate" "${tool%.*}" "${LOCKER_DIR}/${tool} ${args}"
        ;;
      3)
        echo "Signal:"
        echo "Disk: $(df -h "${REPO_ROOT}" 2>/dev/null | tail -n 1)"
        ;;
      4)
        if [ -f "${ENV_FILE}" ]; then
          echo "Config present: ${ENV_FILE}"
          if grep -q '^OPENAI_API_KEY=' "${ENV_FILE}"; then
            echo "OPENAI_API_KEY: set"
          else
            echo "OPENAI_API_KEY: not set"
          fi
          if grep -q '^OPENAI_MODEL=' "${ENV_FILE}"; then
            echo "OPENAI_MODEL: set"
          else
            echo "OPENAI_MODEL: not set"
          fi
        else
          echo "Config missing: ${ENV_FILE}"
        fi
        ;;
      5)
        echo "Overwatch provides a disciplined terminal cockpit for JADIS Arsenal."
        echo "Keybindings: q quit, Enter select, / search (when available)."
        ;;
      q|Q)
        exit 0
        ;;
      *)
        echo "Unknown selection."
        ;;
    esac
  done
fi

disable_mouse_reporting
if is_termux; then
  disable_mouse_reporting
fi

if [ -r /dev/fd/63 ]; then
  python3 /dev/fd/63 63< <(cat <<PY
import asyncio
import json
import os
import platform
import shutil
import shlex
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widgets import Footer, Input, Label, ListItem, ListView, Static, TextArea

SCRIPT_DIR = Path("${SCRIPT_DIR}").resolve()
COCKPIT_DIR = Path("${COCKPIT_DIR}").resolve()
REPO_ROOT = Path("${REPO_ROOT}").resolve()
RUNS_DIR = Path("${RUNS_DIR}").resolve()
CONFIG_DIR = Path("${CONFIG_DIR}").resolve()
ENV_FILE = Path("${ENV_FILE}").resolve()
LOCKER_DIR = Path("${LOCKER_DIR}").resolve()

RUNS_DIR.mkdir(parents=True, exist_ok=True)

def disable_textual_mouse() -> None:
    for attr in ("ENABLE_MOUSE", "enable_mouse", "disable_mouse", "mouse"):
        if hasattr(App, attr):
            try:
                setattr(App, attr, False)
            except Exception:
                pass
            return


def load_env_file(path: Path) -> Dict[str, str]:
    data = {}
    if not path.exists():
        return data

    def strip_inline_comment(value: str) -> str:
        in_single = False
        in_double = False
        for idx, ch in enumerate(value):
            if ch == "'" and not in_double:
                in_single = not in_single
            elif ch == '"' and not in_single:
                in_double = not in_double
            elif ch == "#" and not in_single and not in_double:
                return value[:idx].rstrip()
        return value.rstrip()

    try:
        lines = path.read_text(errors="ignore").splitlines()
    except Exception:
        return data
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = strip_inline_comment(value.strip())
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        data[key.strip()] = value
    return data


def read_tail(path: Path, max_bytes: int) -> str:
    if not path.exists():
        return ""
    try:
        try:
            size = path.stat().st_size
        except FileNotFoundError:
            return ""
        with path.open("rb") as handle:
            try:
                if size > max_bytes:
                    handle.seek(-max_bytes, 2)
            except Exception:
                handle.seek(0)
            data = handle.read()
        return data.decode(errors="ignore")
    except Exception:
        return ""


def safe_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def create_run_dir(mode: str, action: str) -> Path:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = RUNS_DIR / f"{ts}_{mode}_{action}"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def write_metadata(run_dir: Path, mode: str, action: str, command: str, exit_code: int, started: str, ended: str, cwd: Path) -> None:
    metadata = {
        "mode": mode,
        "action": action,
        "command": command,
        "exit_code": exit_code,
        "platform": platform.system(),
        "cwd": str(cwd),
        "started_at": started,
        "ended_at": ended,
    }
    safe_write_text(run_dir / "metadata.json", json.dumps(metadata, indent=2))


def is_destructive(command: str) -> bool:
    lowered = command.lower()
    patterns = [
        "rm -rf",
        "rm -fr",
        "mkfs",
        " shutdown",
        "reboot",
        " dd ",
        "dd ",
        " dd",
    ]
    return any(pattern in lowered for pattern in patterns)


class StatusHeader(Static):
    mode = reactive("Observe")
    ai_status = reactive("AI: unavailable")
    cwd = reactive(str(REPO_ROOT))

    def render(self) -> str:
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        platform_name = platform.system()
        return f"MODE: {self.mode} | {platform_name} | {self.cwd} | {now} | {self.ai_status}"


class NavItem(ListItem):
    def __init__(self, label: str):
        super().__init__(Label(label))
        self.label_text = label


class ObservePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Recent Runs")
        yield Input(placeholder="Filter by keyword...", id="observe-filter")
        yield ListView(id="observe-list")
        yield TextArea(id="observe-output", read_only=True)


class FilesPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Filesystem")
        yield Input(placeholder="Path (Enter to open)", id="files-path")
        yield ListView(id="files-list")
        yield TextArea(id="files-preview", read_only=True)


class CleanupPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Paste snippet or load file for cleanup review")
        yield TextArea(id="cleanup-input")
        yield Horizontal(
            Input(placeholder="File path to load", id="cleanup-file"),
            Label("[Enter] Load", id="cleanup-load", classes="action-label"),
        )
        yield Horizontal(
            Label("[Enter] Analyze", id="cleanup-analyze", classes="action-label"),
            Label("[Enter] Save Notes", id="cleanup-save", classes="action-label"),
        )
        yield TextArea(id="cleanup-analysis", read_only=True)


class OperatePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Locker Tools")
        yield ListView(id="operate-list")
        yield Input(placeholder="Arguments", id="operate-args")
        yield Label("[Enter] Preview / Run", id="operate-run", classes="action-label")
        yield TextArea(id="operate-output", read_only=True)


class SignalPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Signal Overview")
        yield TextArea(id="signal-text", read_only=True)


class ConfigPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Config Status")
        yield TextArea(id="config-text", read_only=True)


class AboutPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("OVERWATCH: SENTINEL / NIGHT OPS")
        yield TextArea(
            "Mission terminal for JADIS Arsenal operations.\n"
            "Keybindings: q quit, Esc back, Tab focus, / search, Enter inspect, s save notes, r refresh, ? help.\n"
            "No destructive actions without confirmation.\n",
            read_only=True,
            id="about-text",
        )


class TerminalPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Terminal")
        yield Horizontal(
            Input(placeholder="Command (runs in selected cwd)", id="terminal-command"),
            Label("[Enter] Run", id="terminal-run", classes="action-label"),
            Label("[Ctrl+C] Cancel", id="terminal-cancel", classes="action-label"),
        )
        yield TextArea(id="terminal-output", read_only=True)


class HelpOverlay(Static):
    def render(self) -> str:
        return (
            "HELP\n"
            "q quit | Esc back | Tab focus | / search | Enter inspect | s save notes | r refresh | ? help\n"
            "Use navigation list to switch modes.\n"
        )


class ConfirmScreen(ModalScreen[str]):
    def __init__(self, prompt: str) -> None:
        super().__init__()
        self.prompt = prompt

    def compose(self) -> ComposeResult:
        yield Label(self.prompt, id="confirm-prompt")
        yield Input(placeholder="Type yes to confirm", id="confirm-input")

    def on_mount(self) -> None:
        self.query_one("#confirm-input", Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value.strip())


class OverwatchApp(App):
    CSS = """
    Screen {
        background: #141517;
        color: #c7cbd1;
    }
    #root {
        height: 100%;
    }
    #header {
        background: #1b1d20;
        color: #c7cbd1;
        padding: 1 2;
        border: solid #2b2f34;
    }
    #left-pane {
        width: 70%;
    }
    #nav {
        background: #191b1f;
        border: solid #3b2b1c;
        width: 24;
    }
    #main {
        border: solid #2b2f34;
        background: #16181b;
        padding: 1 1;
    }
    #terminal-pane {
        border: solid #3b2b1c;
        background: #131416;
        width: 30%;
        padding: 1 1;
    }
    #footer {
        background: #1b1d20;
        color: #9aa3ad;
        border: solid #2b2f34;
    }
    ListView > .list-item--highlight {
        background: #2a1a0a;
        color: #f4a259;
    }
    Input:focus, TextArea:focus {
        border: solid #f4a259;
    }
    .action-label {
        color: #f4a259;
    }
    #help-overlay {
        background: #1b1d20;
        border: solid #f4a259;
        color: #c7cbd1;
        padding: 1 2;
    }
    #confirm-prompt {
        color: #f4a259;
    }
    #terminal-output {
        border: solid #3b2b1c;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("escape", "back", "Back"),
        Binding("tab", "focus_next", "Next Pane"),
        Binding("/", "search", "Search"),
        Binding("enter", "enter", "Enter"),
        Binding("s", "save_notes", "Save Notes"),
        Binding("r", "refresh", "Refresh"),
        Binding("?", "help", "Help"),
        Binding("ctrl+c", "cancel_task", "Cancel"),
    ]

    mode = reactive("Observe")
    help_visible = reactive(False)
    ai_available = reactive(False)

    def compose(self) -> ComposeResult:
        with Vertical(id="root"):
            yield StatusHeader(id="header")
            with Horizontal():
                with Vertical(id="left-pane"):
                    nav_items = [
                        NavItem("Observe"),
                        NavItem("Files"),
                        NavItem("Cleanup"),
                        NavItem("Operate"),
                        NavItem("Signal"),
                        NavItem("Config"),
                        NavItem("About"),
                    ]
                    nav = ListView(*nav_items, id="nav")
                    yield nav
                    with Container(id="main"):
                        self.observe_pane = ObservePane(id="observe-pane")
                        self.files_pane = FilesPane(id="files-pane")
                        self.cleanup_pane = CleanupPane(id="cleanup-pane")
                        self.operate_pane = OperatePane(id="operate-pane")
                        self.signal_pane = SignalPane(id="signal-pane")
                        self.config_pane = ConfigPane(id="config-pane")
                        self.about_pane = AboutPane(id="about-pane")
                        yield self.observe_pane
                        yield self.files_pane
                        yield self.cleanup_pane
                        yield self.operate_pane
                        yield self.signal_pane
                        yield self.config_pane
                        yield self.about_pane
                with Container(id="terminal-pane"):
                    self.terminal_pane = TerminalPane(id="terminal")
                    yield self.terminal_pane
            yield Footer(id="footer")
            self.help_overlay = HelpOverlay(id="help-overlay")
            self.help_overlay.display = False
            yield self.help_overlay

    def on_mount(self) -> None:
        self.active_tasks = set()
        self.cwd = REPO_ROOT
        self.observe_index: List[Path] = []
        self.files_index: List[Path] = []
        self.terminal_task: Optional[asyncio.Task] = None
        self.terminal_process: Optional[asyncio.subprocess.Process] = None
        self.query_one("#nav", ListView).index = 0
        self.update_mode("Observe")
        self.refresh_all()
        self.update_ai_status()
        self.update_cwd_display()

    def update_cwd_display(self) -> None:
        header = self.query_one(StatusHeader)
        header.cwd = str(self.cwd)

    def update_ai_status(self) -> None:
        env = load_env_file(ENV_FILE)
        key_set = "OPENAI_API_KEY" in env and env["OPENAI_API_KEY"]
        model = env.get("OPENAI_MODEL")
        if not model or not model.strip():
            model = "gpt-4o-mini"
        header = self.query_one(StatusHeader)
        analyze_label = self.query_one("#cleanup-analyze", Label)
        self.ai_available = bool(key_set)
        if key_set:
            header.ai_status = f"AI: {model}"
            analyze_label.update("[Enter] Analyze")
        else:
            header.ai_status = "AI: unavailable"
            analyze_label.update("[Enter] Analyze (AI unavailable)")
            self.query_one("#cleanup-analysis", TextArea).text = (
                "AI unavailable: set OPENAI_API_KEY in cockpit/config/.env"
            )

    def refresh_all(self) -> None:
        self.refresh_observe()
        self.refresh_files()
        self.refresh_operate()
        self.refresh_signal()
        self.refresh_config()
        self.update_ai_status()

    def update_mode(self, mode: str) -> None:
        self.mode = mode
        header = self.query_one(StatusHeader)
        header.mode = mode
        self.observe_pane.display = mode == "Observe"
        self.files_pane.display = mode == "Files"
        self.cleanup_pane.display = mode == "Cleanup"
        self.operate_pane.display = mode == "Operate"
        self.signal_pane.display = mode == "Signal"
        self.config_pane.display = mode == "Config"
        self.about_pane.display = mode == "About"

    def action_back(self) -> None:
        self.query_one("#nav", ListView).focus()

    def action_search(self) -> None:
        if self.mode == "Observe":
            self.query_one("#observe-filter", Input).focus()
        elif self.mode == "Files":
            self.query_one("#files-path", Input).focus()

    async def action_enter(self) -> None:
        if self.mode == "Observe":
            self.open_selected_run()
        elif self.mode == "Files":
            focused = self.focused
            if focused and isinstance(focused, Input) and focused.id == "files-path":
                self.open_path_from_input()
            else:
                self.open_selected_file()
        elif self.mode == "Cleanup":
            focused = self.focused
            if focused and isinstance(focused, Input) and focused.id == "cleanup-file":
                self.load_cleanup_file()
            else:
                if not self.ai_available:
                    self.query_one("#cleanup-analysis", TextArea).text = (
                        "AI unavailable: set OPENAI_API_KEY in cockpit/config/.env"
                    )
                    return
                self.run_cleanup_analysis()
        elif self.mode == "Operate":
            await self.run_operate()
        else:
            focused = self.focused
            if focused and isinstance(focused, Input) and focused.id == "terminal-command":
                await self.run_terminal_command()

    async def action_save_notes(self) -> None:
        if self.mode != "Cleanup":
            return
        confirm = await self.push_screen(ConfirmScreen("Save cleanup notes? Type yes to confirm:"))
        if confirm != "yes":
            return
        run_dir = create_run_dir("cleanup", "notes")
        notes = self.query_one("#cleanup-input", TextArea).text.strip()
        analysis = self.query_one("#cleanup-analysis", TextArea).text.strip()
        content = notes
        if analysis:
            content = f"Notes:\n{notes}\n\nAnalysis:\n{analysis}" if notes else f"Analysis:\n{analysis}"
        safe_write_text(run_dir / "notes.txt", content)
        now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        write_metadata(
            run_dir,
            "cleanup",
            "notes",
            "save_notes",
            0,
            now,
            now,
            self.cwd,
        )

    def action_refresh(self) -> None:
        self.refresh_all()

    def action_help(self) -> None:
        self.help_visible = not self.help_visible
        self.help_overlay.display = self.help_visible

    def action_cancel_task(self) -> None:
        if self.terminal_task and not self.terminal_task.done():
            self.terminal_task.cancel()
        for task in list(self.active_tasks):
            if not task.done():
                task.cancel()

    async def action_quit(self) -> None:
        if getattr(self, "active_tasks", None):
            confirm = await self.push_screen(ConfirmScreen("Operations still running. Quit anyway? Type yes to confirm."))
            if confirm != "yes":
                return
            tasks = list(self.active_tasks)
            for task in tasks:
                task.cancel()
            if tasks:
                try:
                    await asyncio.wait_for(asyncio.gather(*tasks, return_exceptions=True), timeout=2)
                except asyncio.TimeoutError:
                    pass
                finally:
                    for task in tasks:
                        self.active_tasks.discard(task)
        if self.terminal_task and not self.terminal_task.done():
            self.terminal_task.cancel()
        self.exit()

    def track_task(self, task: asyncio.Task) -> None:
        self.active_tasks.add(task)
        def _finalize(t: asyncio.Task) -> None:
            self.active_tasks.discard(t)
            try:
                _ = t.exception()
            except asyncio.CancelledError:
                pass
            except Exception:
                pass
        task.add_done_callback(_finalize)

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id == "nav":
            item = event.item
            if isinstance(item, NavItem):
                self.update_mode(item.label_text)

    def set_cwd(self, new_path: Path) -> None:
        try:
            resolved = new_path.expanduser().resolve()
        except Exception:
            resolved = new_path.expanduser()
        if resolved.is_dir():
            self.cwd = resolved
            self.update_cwd_display()
            self.refresh_files()
        else:
            self.query_one("#files-preview", TextArea).text = "Not a directory."

    def refresh_observe(self) -> None:
        list_view = self.query_one("#observe-list", ListView)
        filter_value = self.query_one("#observe-filter", Input).value.strip().lower()
        list_view.clear()
        runs = [path for path in RUNS_DIR.iterdir() if path.is_dir()]
        runs_sorted = sorted(runs, reverse=True)
        self.observe_index = []
        count = 0
        for run in runs_sorted:
            if filter_value and filter_value not in run.name.lower():
                continue
            list_view.append(NavItem(run.name))
            self.observe_index.append(run)
            count += 1
            if count >= 50:
                break
        if self.observe_index:
            list_view.index = 0
            self.open_selected_run()
        else:
            list_view.index = None
            self.query_one("#observe-output", TextArea).text = "No runs yet."

    def open_selected_run(self) -> None:
        list_view = self.query_one("#observe-list", ListView)
        if list_view.index is None:
            return
        if not (0 <= list_view.index < len(self.observe_index)):
            return
        run_dir = self.observe_index[list_view.index]
        output = run_dir / "output.log"
        if not output.exists():
            content = "No output.log found."
        else:
            content = read_tail(output, 20000) or "No output.log found."
        self.query_one("#observe-output", TextArea).text = content[-20000:]

    def refresh_files(self) -> None:
        list_view = self.query_one("#files-list", ListView)
        list_view.clear()
        self.files_index = []
        preview = self.query_one("#files-preview", TextArea)
        try:
            current = self.cwd
            if current.parent != current:
                list_view.append(NavItem(".."))
                self.files_index.append(current.parent)
            entries = sorted(current.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
            for entry in entries:
                label = f"{entry.name}/" if entry.is_dir() else entry.name
                list_view.append(NavItem(label))
                self.files_index.append(entry)
            if not entries and current.parent == current:
                preview.text = "Empty directory."
        except PermissionError:
            preview.text = "Permission denied."
        except FileNotFoundError:
            preview.text = "Directory not found."
        except Exception:
            preview.text = "Unable to read directory."

    def open_selected_file(self) -> None:
        list_view = self.query_one("#files-list", ListView)
        if list_view.index is None:
            return
        if not (0 <= list_view.index < len(self.files_index)):
            return
        target = self.files_index[list_view.index]
        self.open_path(target)

    def open_path_from_input(self) -> None:
        path_value = self.query_one("#files-path", Input).value.strip()
        if not path_value:
            return
        self.open_path(Path(path_value))

    def open_path(self, path: Path) -> None:
        preview = self.query_one("#files-preview", TextArea)
        try:
            resolved = path.expanduser().resolve()
        except Exception:
            resolved = path.expanduser()
        if not resolved.exists():
            preview.text = "Path not found."
            return
        if resolved.is_dir():
            self.set_cwd(resolved)
            preview.text = f"Directory selected: {resolved}"
            return
        try:
            content = read_tail(resolved, 20000)
            preview.text = content if content else "(empty file)"
        except PermissionError:
            preview.text = "Permission denied."
        except Exception:
            preview.text = "Unable to preview file."

    def parse_tool_descriptions(self) -> Dict[str, str]:
        descriptions: Dict[str, str] = {}
        readme = LOCKER_DIR / "README.md"
        if not readme.exists():
            return descriptions
        tools = list(LOCKER_DIR.glob("*.sh"))
        for line in readme.read_text(errors="ignore").splitlines():
            for tool in tools:
                name = tool.name
                if name in line.split():
                    cleaned = line.replace(name, "").strip(" -:\t")
                    if cleaned:
                        descriptions[name] = cleaned
        return descriptions

    def refresh_operate(self) -> None:
        list_view = self.query_one("#operate-list", ListView)
        list_view.clear()
        output_widget = self.query_one("#operate-output", TextArea)
        if not LOCKER_DIR.exists():
            output_widget.text = "Locker directory not found."
            return
        descriptions = self.parse_tool_descriptions()
        self.tool_index = []
        tools = sorted(LOCKER_DIR.glob("*.sh"))
        if not tools:
            list_view.index = None
            output_widget.text = "No tools found in locker/"
            return
        for tool in tools:
            desc = descriptions.get(tool.name, "")
            label = f"{tool.name} - {desc}" if desc else tool.name
            list_view.append(NavItem(label))
            self.tool_index.append(tool.name)

    async def run_operate(self) -> None:
        list_view = self.query_one("#operate-list", ListView)
        if list_view.index is None:
            return
        tool_name = None
        if hasattr(self, "tool_index") and 0 <= list_view.index < len(self.tool_index):
            tool_name = self.tool_index[list_view.index]
        if not tool_name:
            return
        tool = LOCKER_DIR / tool_name
        args_value = self.query_one("#operate-args", Input).value.strip()
        try:
            args = shlex.split(args_value) if args_value else []
        except ValueError:
            self.query_one("#operate-output", TextArea).text = "Invalid arguments: check quoting."
            return
        command = " ".join([str(tool.resolve()), *args]).strip()
        output_widget = self.query_one("#operate-output", TextArea)
        output_widget.text = f"Preview: {command}\nCWD: {self.cwd}\n"
        confirm = await self.push_screen(ConfirmScreen(f"Run {command}? Type yes to confirm:"))
        if confirm != "yes":
            output_widget.text += "Cancelled.\n"
            return
        self.run_command_stream("operate", tool.stem, tool, args, command, output_widget)

    def run_command_stream(self, mode: str, action: str, tool: Path, args: List[str], command: str, output_widget: TextArea) -> None:
        run_dir = create_run_dir(mode, action)
        output_path = run_dir / "output.log"
        started = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        output_widget.text = f"Running: {command}\nCWD: {self.cwd}\n"
        self.refresh()
        async def runner():
            proc = None
            exit_code = 0
            try:
                if tool.exists() and tool.is_file() and os.access(tool, os.X_OK):
                    proc = await asyncio.create_subprocess_exec(
                        str(tool),
                        *args,
                        cwd=str(self.cwd),
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.STDOUT,
                    )
                else:
                    fallback_command = " ".join([shlex.quote(str(tool)), *[shlex.quote(arg) for arg in args]])
                    proc = await asyncio.create_subprocess_exec(
                        "bash",
                        "-lc",
                        fallback_command,
                        cwd=str(self.cwd),
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.STDOUT,
                    )
                with output_path.open("w") as handle:
                    while True:
                        line = await proc.stdout.readline()
                        if not line:
                            break
                        text = line.decode(errors="ignore")
                        handle.write(text)
                        handle.flush()
                        output_widget.text += text
                        output_widget.scroll_end(animate=False)
                    exit_code = await proc.wait()
            except asyncio.CancelledError:
                exit_code = 130
                if proc and proc.returncode is None:
                    proc.terminate()
                    await proc.wait()
                raise
            except Exception:
                exit_code = 1
                message = "Operation failed. Check output log for details."
                output_widget.text += f"{message}\n"
                safe_write_text(output_path, output_widget.text)
            finally:
                ended = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                write_metadata(run_dir, mode, action, command, exit_code, started, ended, self.cwd)
        task = asyncio.create_task(runner())
        self.track_task(task)

    async def run_terminal_command(self) -> None:
        input_widget = self.query_one("#terminal-command", Input)
        output_widget = self.query_one("#terminal-output", TextArea)
        command = input_widget.value.strip()
        if not command:
            return
        output_widget.text = f"Preview: {command}\nCWD: {self.cwd}\n"
        if is_destructive(command):
            confirm = await self.push_screen(ConfirmScreen("Destructive command detected. Type yes to confirm:"))
            if confirm != "yes":
                output_widget.text += "Cancelled.\n"
                return
        run_dir = create_run_dir("terminal", "run")
        output_path = run_dir / "output.log"
        started = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        input_widget.value = ""
        async def runner():
            exit_code = 0
            proc = None
            try:
                proc = await asyncio.create_subprocess_exec(
                    "bash",
                    "-lc",
                    command,
                    cwd=str(self.cwd),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                )
                self.terminal_process = proc
                with output_path.open("w") as handle:
                    while True:
                        line = await proc.stdout.readline()
                        if not line:
                            break
                        text = line.decode(errors="ignore")
                        handle.write(text)
                        handle.flush()
                        output_widget.text += text
                        output_widget.scroll_end(animate=False)
                    exit_code = await proc.wait()
            except asyncio.CancelledError:
                exit_code = 130
                if proc and proc.returncode is None:
                    proc.terminate()
                    await proc.wait()
                output_widget.text += "\nCancelled.\n"
                raise
            except Exception:
                exit_code = 1
                output_widget.text += "\nTerminal command failed.\n"
            finally:
                ended = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                write_metadata(run_dir, "terminal", "run", command, exit_code, started, ended, self.cwd)
                self.terminal_process = None
        task = asyncio.create_task(runner())
        self.terminal_task = task
        self.track_task(task)

    def refresh_signal(self) -> None:
        text = []
        failures = []
        for run in sorted(RUNS_DIR.glob("*"), reverse=True)[:20]:
            meta = run / "metadata.json"
            if meta.exists():
                try:
                    data = json.loads(meta.read_text(errors="ignore"))
                except Exception:
                    continue
                try:
                    exit_code = int(data.get("exit_code", 0))
                except (TypeError, ValueError):
                    exit_code = 0
                if exit_code != 0:
                    failures.append(f"{run.name}: exit {exit_code}")
        text.append("Recent failures:")
        text.extend(failures or ["None detected."])
        missing = []
        if not shutil.which("python3"):
            missing.append("python3 missing")
        if not shutil.which("curl"):
            missing.append("curl missing (AI advisory may be limited)")
        env = load_env_file(ENV_FILE)
        if not ENV_FILE.exists():
            missing.append("Config missing: cockpit/config/.env")
        if "OPENAI_API_KEY" not in env:
            missing.append("OPENAI_API_KEY not configured")
        if "OPENAI_MODEL" not in env:
            missing.append("OPENAI_MODEL not configured")
        text.append("\nWarnings:")
        text.extend(missing or ["None."])
        try:
            usage = shutil.disk_usage(str(self.cwd))
            text.append(f"\nDisk: {usage.free // (1024**3)} GiB free")
        except Exception:
            text.append("\nDisk: unavailable")
        self.query_one("#signal-text", TextArea).text = "\n".join(text)

    def refresh_config(self) -> None:
        text = []
        text.append(f"Config file: {ENV_FILE}")
        if ENV_FILE.exists():
            text.append("Status: present")
            env = load_env_file(ENV_FILE)
            text.append("OPENAI_API_KEY: set" if env.get("OPENAI_API_KEY") else "OPENAI_API_KEY: not set")
            text.append("OPENAI_MODEL: set" if env.get("OPENAI_MODEL") else "OPENAI_MODEL: not set")
            perms = oct(ENV_FILE.stat().st_mode & 0o777)
            text.append(f"Permissions: {perms}")
        else:
            text.append("Status: missing")
        self.query_one("#config-text", TextArea).text = "\n".join(text)

    def load_cleanup_file(self) -> None:
        path = self.query_one("#cleanup-file", Input).value.strip()
        if not path:
            return
        file_path = Path(path)
        if not file_path.exists():
            self.query_one("#cleanup-analysis", TextArea).text = "File not found."
            return
        try:
            content = file_path.read_text(errors="ignore")
        except Exception:
            content = ""
        self.query_one("#cleanup-input", TextArea).text = content or ""

    def run_cleanup_analysis(self) -> None:
        env = load_env_file(ENV_FILE)
        key = env.get("OPENAI_API_KEY")
        model = env.get("OPENAI_MODEL")
        base_url = env.get("OPENAI_BASE_URL") or "https://api.openai.com/v1"
        timeout_value = env.get("OPENAI_TIMEOUT")
        max_output_tokens = env.get("OPENAI_MAX_OUTPUT_TOKENS")
        if not model or not model.strip():
            model = "gpt-4o-mini"
        if not key:
            self.query_one("#cleanup-analysis", TextArea).text = (
                "AI unavailable: set OPENAI_API_KEY in cockpit/config/.env"
            )
            return
        snippet = self.query_one("#cleanup-input", TextArea).text.strip()
        if not snippet:
            self.query_one("#cleanup-analysis", TextArea).text = "Paste a snippet or load a file first."
            return
        run_dir = create_run_dir("cleanup", "analysis")
        prompt = (
            "Review the following snippet for issues and suggestions. "
            "Provide concise analysis.\n\n"
            f"{snippet}"
        )
        payload = {"model": model, "input": prompt, "temperature": 0.2}
        try:
            if max_output_tokens and str(max_output_tokens).strip().isdigit():
                payload["max_output_tokens"] = int(str(max_output_tokens).strip())
        except Exception:
            pass
        timeout = 60
        try:
            if timeout_value:
                timeout = int(str(timeout_value).strip())
        except Exception:
            timeout = 60
        output_widget = self.query_one("#cleanup-analysis", TextArea)
        output_widget.text = "Requesting advisory analysis..."

        async def call_api():
            import urllib.request
            import socket
            import urllib.error
            exit_code = 0
            content = ""
            try:
                req = urllib.request.Request(
                    f"{base_url.rstrip('/')}/responses",
                    data=json.dumps(payload).encode("utf-8"),
                    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                )
                with urllib.request.urlopen(req, timeout=timeout) as response:
                    data = json.loads(response.read().decode("utf-8"))
                content = data.get("output_text") or ""
                if not content:
                    output = data.get("output") or []
                    if output:
                        first = output[0]
                        content_items = first.get("content") or []
                        if content_items:
                            content = content_items[0].get("text", "") or ""
                if not content:
                    content = "AI advisory returned no content."
            except asyncio.CancelledError:
                content = "AI advisory cancelled."
                exit_code = 130
                raise
            except (socket.timeout, urllib.error.URLError):
                content = (
                    "AI advisory timed out or could not reach the network. "
                    "Check connectivity and OPENAI_* settings, then retry."
                )
                exit_code = 1
            except Exception:
                content = (
                    "AI advisory failed. Verify OPENAI_* settings and try again."
                )
                exit_code = 1
            finally:
                output_widget.text = content
                safe_write_text(run_dir / "output.log", content)
                now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                write_metadata(run_dir, "cleanup", "analysis", "ai_advisory", exit_code, now, now, self.cwd)

        task = asyncio.create_task(call_api())
        self.track_task(task)

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "observe-filter":
            self.refresh_observe()

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "cleanup-file":
            self.load_cleanup_file()
        elif event.input.id == "observe-filter":
            self.refresh_observe()
        elif event.input.id == "files-path":
            self.open_path_from_input()
        elif event.input.id == "terminal-command":
            await self.run_terminal_command()


if __name__ == "__main__":
    disable_textual_mouse()
    app = OverwatchApp()
    app.run()
PY
  )
else
  TEMP_PY_FILE="$(mktemp -t overwatch.XXXXXX.py)"
  cat >"${TEMP_PY_FILE}" <<PY
import asyncio
import json
import os
import platform
import shutil
import shlex
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widgets import Footer, Input, Label, ListItem, ListView, Static, TextArea

SCRIPT_DIR = Path("${SCRIPT_DIR}").resolve()
COCKPIT_DIR = Path("${COCKPIT_DIR}").resolve()
REPO_ROOT = Path("${REPO_ROOT}").resolve()
RUNS_DIR = Path("${RUNS_DIR}").resolve()
CONFIG_DIR = Path("${CONFIG_DIR}").resolve()
ENV_FILE = Path("${ENV_FILE}").resolve()
LOCKER_DIR = Path("${LOCKER_DIR}").resolve()

RUNS_DIR.mkdir(parents=True, exist_ok=True)

def disable_textual_mouse() -> None:
    for attr in ("ENABLE_MOUSE", "enable_mouse", "disable_mouse", "mouse"):
        if hasattr(App, attr):
            try:
                setattr(App, attr, False)
            except Exception:
                pass
            return


def load_env_file(path: Path) -> Dict[str, str]:
    data = {}
    if not path.exists():
        return data

    def strip_inline_comment(value: str) -> str:
        in_single = False
        in_double = False
        for idx, ch in enumerate(value):
            if ch == "'" and not in_double:
                in_single = not in_single
            elif ch == '"' and not in_single:
                in_double = not in_double
            elif ch == "#" and not in_single and not in_double:
                return value[:idx].rstrip()
        return value.rstrip()

    try:
        lines = path.read_text(errors="ignore").splitlines()
    except Exception:
        return data
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = strip_inline_comment(value.strip())
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        data[key.strip()] = value
    return data


def read_tail(path: Path, max_bytes: int) -> str:
    if not path.exists():
        return ""
    try:
        try:
            size = path.stat().st_size
        except FileNotFoundError:
            return ""
        with path.open("rb") as handle:
            try:
                if size > max_bytes:
                    handle.seek(-max_bytes, 2)
            except Exception:
                handle.seek(0)
            data = handle.read()
        return data.decode(errors="ignore")
    except Exception:
        return ""


def safe_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def create_run_dir(mode: str, action: str) -> Path:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = RUNS_DIR / f"{ts}_{mode}_{action}"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def write_metadata(run_dir: Path, mode: str, action: str, command: str, exit_code: int, started: str, ended: str, cwd: Path) -> None:
    metadata = {
        "mode": mode,
        "action": action,
        "command": command,
        "exit_code": exit_code,
        "platform": platform.system(),
        "cwd": str(cwd),
        "started_at": started,
        "ended_at": ended,
    }
    safe_write_text(run_dir / "metadata.json", json.dumps(metadata, indent=2))


def is_destructive(command: str) -> bool:
    lowered = command.lower()
    patterns = [
        "rm -rf",
        "rm -fr",
        "mkfs",
        " shutdown",
        "reboot",
        " dd ",
        "dd ",
        " dd",
    ]
    return any(pattern in lowered for pattern in patterns)


class StatusHeader(Static):
    mode = reactive("Observe")
    ai_status = reactive("AI: unavailable")
    cwd = reactive(str(REPO_ROOT))

    def render(self) -> str:
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        platform_name = platform.system()
        return f"MODE: {self.mode} | {platform_name} | {self.cwd} | {now} | {self.ai_status}"


class NavItem(ListItem):
    def __init__(self, label: str):
        super().__init__(Label(label))
        self.label_text = label


class ObservePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Recent Runs")
        yield Input(placeholder="Filter by keyword...", id="observe-filter")
        yield ListView(id="observe-list")
        yield TextArea(id="observe-output", read_only=True)


class FilesPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Filesystem")
        yield Input(placeholder="Path (Enter to open)", id="files-path")
        yield ListView(id="files-list")
        yield TextArea(id="files-preview", read_only=True)


class CleanupPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Paste snippet or load file for cleanup review")
        yield TextArea(id="cleanup-input")
        yield Horizontal(
            Input(placeholder="File path to load", id="cleanup-file"),
            Label("[Enter] Load", id="cleanup-load", classes="action-label"),
        )
        yield Horizontal(
            Label("[Enter] Analyze", id="cleanup-analyze", classes="action-label"),
            Label("[Enter] Save Notes", id="cleanup-save", classes="action-label"),
        )
        yield TextArea(id="cleanup-analysis", read_only=True)


class OperatePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Locker Tools")
        yield ListView(id="operate-list")
        yield Input(placeholder="Arguments", id="operate-args")
        yield Label("[Enter] Preview / Run", id="operate-run", classes="action-label")
        yield TextArea(id="operate-output", read_only=True)


class SignalPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Signal Overview")
        yield TextArea(id="signal-text", read_only=True)


class ConfigPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Config Status")
        yield TextArea(id="config-text", read_only=True)


class AboutPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("OVERWATCH: SENTINEL / NIGHT OPS")
        yield TextArea(
            "Mission terminal for JADIS Arsenal operations.\n"
            "Keybindings: q quit, Esc back, Tab focus, / search, Enter inspect, s save notes, r refresh, ? help.\n"
            "No destructive actions without confirmation.\n",
            read_only=True,
            id="about-text",
        )


class TerminalPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Terminal")
        yield Horizontal(
            Input(placeholder="Command (runs in selected cwd)", id="terminal-command"),
            Label("[Enter] Run", id="terminal-run", classes="action-label"),
            Label("[Ctrl+C] Cancel", id="terminal-cancel", classes="action-label"),
        )
        yield TextArea(id="terminal-output", read_only=True)


class HelpOverlay(Static):
    def render(self) -> str:
        return (
            "HELP\n"
            "q quit | Esc back | Tab focus | / search | Enter inspect | s save notes | r refresh | ? help\n"
            "Use navigation list to switch modes.\n"
        )


class ConfirmScreen(ModalScreen[str]):
    def __init__(self, prompt: str) -> None:
        super().__init__()
        self.prompt = prompt

    def compose(self) -> ComposeResult:
        yield Label(self.prompt, id="confirm-prompt")
        yield Input(placeholder="Type yes to confirm", id="confirm-input")

    def on_mount(self) -> None:
        self.query_one("#confirm-input", Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value.strip())


class OverwatchApp(App):
    CSS = """
    Screen {
        background: #141517;
        color: #c7cbd1;
    }
    #root {
        height: 100%;
    }
    #header {
        background: #1b1d20;
        color: #c7cbd1;
        padding: 1 2;
        border: solid #2b2f34;
    }
    #left-pane {
        width: 70%;
    }
    #nav {
        background: #191b1f;
        border: solid #3b2b1c;
        width: 24;
    }
    #main {
        border: solid #2b2f34;
        background: #16181b;
        padding: 1 1;
    }
    #terminal-pane {
        border: solid #3b2b1c;
        background: #131416;
        width: 30%;
        padding: 1 1;
    }
    #footer {
        background: #1b1d20;
        color: #9aa3ad;
        border: solid #2b2f34;
    }
    ListView > .list-item--highlight {
        background: #2a1a0a;
        color: #f4a259;
    }
    Input:focus, TextArea:focus {
        border: solid #f4a259;
    }
    .action-label {
        color: #f4a259;
    }
    #help-overlay {
        background: #1b1d20;
        border: solid #f4a259;
        color: #c7cbd1;
        padding: 1 2;
    }
    #confirm-prompt {
        color: #f4a259;
    }
    #terminal-output {
        border: solid #3b2b1c;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("escape", "back", "Back"),
        Binding("tab", "focus_next", "Next Pane"),
        Binding("/", "search", "Search"),
        Binding("enter", "enter", "Enter"),
        Binding("s", "save_notes", "Save Notes"),
        Binding("r", "refresh", "Refresh"),
        Binding("?", "help", "Help"),
        Binding("ctrl+c", "cancel_task", "Cancel"),
    ]

    mode = reactive("Observe")
    help_visible = reactive(False)
    ai_available = reactive(False)

    def compose(self) -> ComposeResult:
        with Vertical(id="root"):
            yield StatusHeader(id="header")
            with Horizontal():
                with Vertical(id="left-pane"):
                    nav_items = [
                        NavItem("Observe"),
                        NavItem("Files"),
                        NavItem("Cleanup"),
                        NavItem("Operate"),
                        NavItem("Signal"),
                        NavItem("Config"),
                        NavItem("About"),
                    ]
                    nav = ListView(*nav_items, id="nav")
                    yield nav
                    with Container(id="main"):
                        self.observe_pane = ObservePane(id="observe-pane")
                        self.files_pane = FilesPane(id="files-pane")
                        self.cleanup_pane = CleanupPane(id="cleanup-pane")
                        self.operate_pane = OperatePane(id="operate-pane")
                        self.signal_pane = SignalPane(id="signal-pane")
                        self.config_pane = ConfigPane(id="config-pane")
                        self.about_pane = AboutPane(id="about-pane")
                        yield self.observe_pane
                        yield self.files_pane
                        yield self.cleanup_pane
                        yield self.operate_pane
                        yield self.signal_pane
                        yield self.config_pane
                        yield self.about_pane
                with Container(id="terminal-pane"):
                    self.terminal_pane = TerminalPane(id="terminal")
                    yield self.terminal_pane
            yield Footer(id="footer")
            self.help_overlay = HelpOverlay(id="help-overlay")
            self.help_overlay.display = False
            yield self.help_overlay

    def on_mount(self) -> None:
        self.active_tasks = set()
        self.cwd = REPO_ROOT
        self.observe_index: List[Path] = []
        self.files_index: List[Path] = []
        self.terminal_task: Optional[asyncio.Task] = None
        self.terminal_process: Optional[asyncio.subprocess.Process] = None
        self.query_one("#nav", ListView).index = 0
        self.update_mode("Observe")
        self.refresh_all()
        self.update_ai_status()
        self.update_cwd_display()

    def update_cwd_display(self) -> None:
        header = self.query_one(StatusHeader)
        header.cwd = str(self.cwd)

    def update_ai_status(self) -> None:
        env = load_env_file(ENV_FILE)
        key_set = "OPENAI_API_KEY" in env and env["OPENAI_API_KEY"]
        model = env.get("OPENAI_MODEL")
        if not model or not model.strip():
            model = "gpt-4o-mini"
        header = self.query_one(StatusHeader)
        analyze_label = self.query_one("#cleanup-analyze", Label)
        self.ai_available = bool(key_set)
        if key_set:
            header.ai_status = f"AI: {model}"
            analyze_label.update("[Enter] Analyze")
        else:
            header.ai_status = "AI: unavailable"
            analyze_label.update("[Enter] Analyze (AI unavailable)")
            self.query_one("#cleanup-analysis", TextArea).text = (
                "AI unavailable: set OPENAI_API_KEY in cockpit/config/.env"
            )

    def refresh_all(self) -> None:
        self.refresh_observe()
        self.refresh_files()
        self.refresh_operate()
        self.refresh_signal()
        self.refresh_config()
        self.update_ai_status()

    def update_mode(self, mode: str) -> None:
        self.mode = mode
        header = self.query_one(StatusHeader)
        header.mode = mode
        self.observe_pane.display = mode == "Observe"
        self.files_pane.display = mode == "Files"
        self.cleanup_pane.display = mode == "Cleanup"
        self.operate_pane.display = mode == "Operate"
        self.signal_pane.display = mode == "Signal"
        self.config_pane.display = mode == "Config"
        self.about_pane.display = mode == "About"

    def action_back(self) -> None:
        self.query_one("#nav", ListView).focus()

    def action_search(self) -> None:
        if self.mode == "Observe":
            self.query_one("#observe-filter", Input).focus()
        elif self.mode == "Files":
            self.query_one("#files-path", Input).focus()

    async def action_enter(self) -> None:
        if self.mode == "Observe":
            self.open_selected_run()
        elif self.mode == "Files":
            focused = self.focused
            if focused and isinstance(focused, Input) and focused.id == "files-path":
                self.open_path_from_input()
            else:
                self.open_selected_file()
        elif self.mode == "Cleanup":
            focused = self.focused
            if focused and isinstance(focused, Input) and focused.id == "cleanup-file":
                self.load_cleanup_file()
            else:
                if not self.ai_available:
                    self.query_one("#cleanup-analysis", TextArea).text = (
                        "AI unavailable: set OPENAI_API_KEY in cockpit/config/.env"
                    )
                    return
                self.run_cleanup_analysis()
        elif self.mode == "Operate":
            await self.run_operate()
        else:
            focused = self.focused
            if focused and isinstance(focused, Input) and focused.id == "terminal-command":
                await self.run_terminal_command()

    async def action_save_notes(self) -> None:
        if self.mode != "Cleanup":
            return
        confirm = await self.push_screen(ConfirmScreen("Save cleanup notes? Type yes to confirm:"))
        if confirm != "yes":
            return
        run_dir = create_run_dir("cleanup", "notes")
        notes = self.query_one("#cleanup-input", TextArea).text.strip()
        analysis = self.query_one("#cleanup-analysis", TextArea).text.strip()
        content = notes
        if analysis:
            content = f"Notes:\n{notes}\n\nAnalysis:\n{analysis}" if notes else f"Analysis:\n{analysis}"
        safe_write_text(run_dir / "notes.txt", content)
        now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        write_metadata(
            run_dir,
            "cleanup",
            "notes",
            "save_notes",
            0,
            now,
            now,
            self.cwd,
        )

    def action_refresh(self) -> None:
        self.refresh_all()

    def action_help(self) -> None:
        self.help_visible = not self.help_visible
        self.help_overlay.display = self.help_visible

    def action_cancel_task(self) -> None:
        if self.terminal_task and not self.terminal_task.done():
            self.terminal_task.cancel()
        for task in list(self.active_tasks):
            if not task.done():
                task.cancel()

    async def action_quit(self) -> None:
        if getattr(self, "active_tasks", None):
            confirm = await self.push_screen(ConfirmScreen("Operations still running. Quit anyway? Type yes to confirm."))
            if confirm != "yes":
                return
            tasks = list(self.active_tasks)
            for task in tasks:
                task.cancel()
            if tasks:
                try:
                    await asyncio.wait_for(asyncio.gather(*tasks, return_exceptions=True), timeout=2)
                except asyncio.TimeoutError:
                    pass
                finally:
                    for task in tasks:
                        self.active_tasks.discard(task)
        if self.terminal_task and not self.terminal_task.done():
            self.terminal_task.cancel()
        self.exit()

    def track_task(self, task: asyncio.Task) -> None:
        self.active_tasks.add(task)
        def _finalize(t: asyncio.Task) -> None:
            self.active_tasks.discard(t)
            try:
                _ = t.exception()
            except asyncio.CancelledError:
                pass
            except Exception:
                pass
        task.add_done_callback(_finalize)

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id == "nav":
            item = event.item
            if isinstance(item, NavItem):
                self.update_mode(item.label_text)

    def set_cwd(self, new_path: Path) -> None:
        try:
            resolved = new_path.expanduser().resolve()
        except Exception:
            resolved = new_path.expanduser()
        if resolved.is_dir():
            self.cwd = resolved
            self.update_cwd_display()
            self.refresh_files()
        else:
            self.query_one("#files-preview", TextArea).text = "Not a directory."

    def refresh_observe(self) -> None:
        list_view = self.query_one("#observe-list", ListView)
        filter_value = self.query_one("#observe-filter", Input).value.strip().lower()
        list_view.clear()
        runs = [path for path in RUNS_DIR.iterdir() if path.is_dir()]
        runs_sorted = sorted(runs, reverse=True)
        self.observe_index = []
        count = 0
        for run in runs_sorted:
            if filter_value and filter_value not in run.name.lower():
                continue
            list_view.append(NavItem(run.name))
            self.observe_index.append(run)
            count += 1
            if count >= 50:
                break
        if self.observe_index:
            list_view.index = 0
            self.open_selected_run()
        else:
            list_view.index = None
            self.query_one("#observe-output", TextArea).text = "No runs yet."

    def open_selected_run(self) -> None:
        list_view = self.query_one("#observe-list", ListView)
        if list_view.index is None:
            return
        if not (0 <= list_view.index < len(self.observe_index)):
            return
        run_dir = self.observe_index[list_view.index]
        output = run_dir / "output.log"
        if not output.exists():
            content = "No output.log found."
        else:
            content = read_tail(output, 20000) or "No output.log found."
        self.query_one("#observe-output", TextArea).text = content[-20000:]

    def refresh_files(self) -> None:
        list_view = self.query_one("#files-list", ListView)
        list_view.clear()
        self.files_index = []
        preview = self.query_one("#files-preview", TextArea)
        try:
            current = self.cwd
            if current.parent != current:
                list_view.append(NavItem(".."))
                self.files_index.append(current.parent)
            entries = sorted(current.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
            for entry in entries:
                label = f"{entry.name}/" if entry.is_dir() else entry.name
                list_view.append(NavItem(label))
                self.files_index.append(entry)
            if not entries and current.parent == current:
                preview.text = "Empty directory."
        except PermissionError:
            preview.text = "Permission denied."
        except FileNotFoundError:
            preview.text = "Directory not found."
        except Exception:
            preview.text = "Unable to read directory."

    def open_selected_file(self) -> None:
        list_view = self.query_one("#files-list", ListView)
        if list_view.index is None:
            return
        if not (0 <= list_view.index < len(self.files_index)):
            return
        target = self.files_index[list_view.index]
        self.open_path(target)

    def open_path_from_input(self) -> None:
        path_value = self.query_one("#files-path", Input).value.strip()
        if not path_value:
            return
        self.open_path(Path(path_value))

    def open_path(self, path: Path) -> None:
        preview = self.query_one("#files-preview", TextArea)
        try:
            resolved = path.expanduser().resolve()
        except Exception:
            resolved = path.expanduser()
        if not resolved.exists():
            preview.text = "Path not found."
            return
        if resolved.is_dir():
            self.set_cwd(resolved)
            preview.text = f"Directory selected: {resolved}"
            return
        try:
            content = read_tail(resolved, 20000)
            preview.text = content if content else "(empty file)"
        except PermissionError:
            preview.text = "Permission denied."
        except Exception:
            preview.text = "Unable to preview file."

    def parse_tool_descriptions(self) -> Dict[str, str]:
        descriptions: Dict[str, str] = {}
        readme = LOCKER_DIR / "README.md"
        if not readme.exists():
            return descriptions
        tools = list(LOCKER_DIR.glob("*.sh"))
        for line in readme.read_text(errors="ignore").splitlines():
            for tool in tools:
                name = tool.name
                if name in line.split():
                    cleaned = line.replace(name, "").strip(" -:\t")
                    if cleaned:
                        descriptions[name] = cleaned
        return descriptions

    def refresh_operate(self) -> None:
        list_view = self.query_one("#operate-list", ListView)
        list_view.clear()
        output_widget = self.query_one("#operate-output", TextArea)
        if not LOCKER_DIR.exists():
            output_widget.text = "Locker directory not found."
            return
        descriptions = self.parse_tool_descriptions()
        self.tool_index = []
        tools = sorted(LOCKER_DIR.glob("*.sh"))
        if not tools:
            list_view.index = None
            output_widget.text = "No tools found in locker/"
            return
        for tool in tools:
            desc = descriptions.get(tool.name, "")
            label = f"{tool.name} - {desc}" if desc else tool.name
            list_view.append(NavItem(label))
            self.tool_index.append(tool.name)

    async def run_operate(self) -> None:
        list_view = self.query_one("#operate-list", ListView)
        if list_view.index is None:
            return
        tool_name = None
        if hasattr(self, "tool_index") and 0 <= list_view.index < len(self.tool_index):
            tool_name = self.tool_index[list_view.index]
        if not tool_name:
            return
        tool = LOCKER_DIR / tool_name
        args_value = self.query_one("#operate-args", Input).value.strip()
        try:
            args = shlex.split(args_value) if args_value else []
        except ValueError:
            self.query_one("#operate-output", TextArea).text = "Invalid arguments: check quoting."
            return
        command = " ".join([str(tool.resolve()), *args]).strip()
        output_widget = self.query_one("#operate-output", TextArea)
        output_widget.text = f"Preview: {command}\nCWD: {self.cwd}\n"
        confirm = await self.push_screen(ConfirmScreen(f"Run {command}? Type yes to confirm:"))
        if confirm != "yes":
            output_widget.text += "Cancelled.\n"
            return
        self.run_command_stream("operate", tool.stem, tool, args, command, output_widget)

    def run_command_stream(self, mode: str, action: str, tool: Path, args: List[str], command: str, output_widget: TextArea) -> None:
        run_dir = create_run_dir(mode, action)
        output_path = run_dir / "output.log"
        started = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        output_widget.text = f"Running: {command}\nCWD: {self.cwd}\n"
        self.refresh()
        async def runner():
            proc = None
            exit_code = 0
            try:
                if tool.exists() and tool.is_file() and os.access(tool, os.X_OK):
                    proc = await asyncio.create_subprocess_exec(
                        str(tool),
                        *args,
                        cwd=str(self.cwd),
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.STDOUT,
                    )
                else:
                    fallback_command = " ".join([shlex.quote(str(tool)), *[shlex.quote(arg) for arg in args]])
                    proc = await asyncio.create_subprocess_exec(
                        "bash",
                        "-lc",
                        fallback_command,
                        cwd=str(self.cwd),
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.STDOUT,
                    )
                with output_path.open("w") as handle:
                    while True:
                        line = await proc.stdout.readline()
                        if not line:
                            break
                        text = line.decode(errors="ignore")
                        handle.write(text)
                        handle.flush()
                        output_widget.text += text
                        output_widget.scroll_end(animate=False)
                    exit_code = await proc.wait()
            except asyncio.CancelledError:
                exit_code = 130
                if proc and proc.returncode is None:
                    proc.terminate()
                    await proc.wait()
                raise
            except Exception:
                exit_code = 1
                message = "Operation failed. Check output log for details."
                output_widget.text += f"{message}\n"
                safe_write_text(output_path, output_widget.text)
            finally:
                ended = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                write_metadata(run_dir, mode, action, command, exit_code, started, ended, self.cwd)
        task = asyncio.create_task(runner())
        self.track_task(task)

    async def run_terminal_command(self) -> None:
        input_widget = self.query_one("#terminal-command", Input)
        output_widget = self.query_one("#terminal-output", TextArea)
        command = input_widget.value.strip()
        if not command:
            return
        output_widget.text = f"Preview: {command}\nCWD: {self.cwd}\n"
        if is_destructive(command):
            confirm = await self.push_screen(ConfirmScreen("Destructive command detected. Type yes to confirm:"))
            if confirm != "yes":
                output_widget.text += "Cancelled.\n"
                return
        run_dir = create_run_dir("terminal", "run")
        output_path = run_dir / "output.log"
        started = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        input_widget.value = ""
        async def runner():
            exit_code = 0
            proc = None
            try:
                proc = await asyncio.create_subprocess_exec(
                    "bash",
                    "-lc",
                    command,
                    cwd=str(self.cwd),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                )
                self.terminal_process = proc
                with output_path.open("w") as handle:
                    while True:
                        line = await proc.stdout.readline()
                        if not line:
                            break
                        text = line.decode(errors="ignore")
                        handle.write(text)
                        handle.flush()
                        output_widget.text += text
                        output_widget.scroll_end(animate=False)
                    exit_code = await proc.wait()
            except asyncio.CancelledError:
                exit_code = 130
                if proc and proc.returncode is None:
                    proc.terminate()
                    await proc.wait()
                output_widget.text += "\nCancelled.\n"
                raise
            except Exception:
                exit_code = 1
                output_widget.text += "\nTerminal command failed.\n"
            finally:
                ended = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                write_metadata(run_dir, "terminal", "run", command, exit_code, started, ended, self.cwd)
                self.terminal_process = None
        task = asyncio.create_task(runner())
        self.terminal_task = task
        self.track_task(task)

    def refresh_signal(self) -> None:
        text = []
        failures = []
        for run in sorted(RUNS_DIR.glob("*"), reverse=True)[:20]:
            meta = run / "metadata.json"
            if meta.exists():
                try:
                    data = json.loads(meta.read_text(errors="ignore"))
                except Exception:
                    continue
                try:
                    exit_code = int(data.get("exit_code", 0))
                except (TypeError, ValueError):
                    exit_code = 0
                if exit_code != 0:
                    failures.append(f"{run.name}: exit {exit_code}")
        text.append("Recent failures:")
        text.extend(failures or ["None detected."])
        missing = []
        if not shutil.which("python3"):
            missing.append("python3 missing")
        if not shutil.which("curl"):
            missing.append("curl missing (AI advisory may be limited)")
        env = load_env_file(ENV_FILE)
        if not ENV_FILE.exists():
            missing.append("Config missing: cockpit/config/.env")
        if "OPENAI_API_KEY" not in env:
            missing.append("OPENAI_API_KEY not configured")
        if "OPENAI_MODEL" not in env:
            missing.append("OPENAI_MODEL not configured")
        text.append("\nWarnings:")
        text.extend(missing or ["None."])
        try:
            usage = shutil.disk_usage(str(self.cwd))
            text.append(f"\nDisk: {usage.free // (1024**3)} GiB free")
        except Exception:
            text.append("\nDisk: unavailable")
        self.query_one("#signal-text", TextArea).text = "\n".join(text)

    def refresh_config(self) -> None:
        text = []
        text.append(f"Config file: {ENV_FILE}")
        if ENV_FILE.exists():
            text.append("Status: present")
            env = load_env_file(ENV_FILE)
            text.append("OPENAI_API_KEY: set" if env.get("OPENAI_API_KEY") else "OPENAI_API_KEY: not set")
            text.append("OPENAI_MODEL: set" if env.get("OPENAI_MODEL") else "OPENAI_MODEL: not set")
            perms = oct(ENV_FILE.stat().st_mode & 0o777)
            text.append(f"Permissions: {perms}")
        else:
            text.append("Status: missing")
        self.query_one("#config-text", TextArea).text = "\n".join(text)

    def load_cleanup_file(self) -> None:
        path = self.query_one("#cleanup-file", Input).value.strip()
        if not path:
            return
        file_path = Path(path)
        if not file_path.exists():
            self.query_one("#cleanup-analysis", TextArea).text = "File not found."
            return
        try:
            content = file_path.read_text(errors="ignore")
        except Exception:
            content = ""
        self.query_one("#cleanup-input", TextArea).text = content or ""

    def run_cleanup_analysis(self) -> None:
        env = load_env_file(ENV_FILE)
        key = env.get("OPENAI_API_KEY")
        model = env.get("OPENAI_MODEL")
        base_url = env.get("OPENAI_BASE_URL") or "https://api.openai.com/v1"
        timeout_value = env.get("OPENAI_TIMEOUT")
        max_output_tokens = env.get("OPENAI_MAX_OUTPUT_TOKENS")
        if not model or not model.strip():
            model = "gpt-4o-mini"
        if not key:
            self.query_one("#cleanup-analysis", TextArea).text = (
                "AI unavailable: set OPENAI_API_KEY in cockpit/config/.env"
            )
            return
        snippet = self.query_one("#cleanup-input", TextArea).text.strip()
        if not snippet:
            self.query_one("#cleanup-analysis", TextArea).text = "Paste a snippet or load a file first."
            return
        run_dir = create_run_dir("cleanup", "analysis")
        prompt = (
            "Review the following snippet for issues and suggestions. "
            "Provide concise analysis.\n\n"
            f"{snippet}"
        )
        payload = {"model": model, "input": prompt, "temperature": 0.2}
        try:
            if max_output_tokens and str(max_output_tokens).strip().isdigit():
                payload["max_output_tokens"] = int(str(max_output_tokens).strip())
        except Exception:
            pass
        timeout = 60
        try:
            if timeout_value:
                timeout = int(str(timeout_value).strip())
        except Exception:
            timeout = 60
        output_widget = self.query_one("#cleanup-analysis", TextArea)
        output_widget.text = "Requesting advisory analysis..."

        async def call_api():
            import urllib.request
            import socket
            import urllib.error
            exit_code = 0
            content = ""
            try:
                req = urllib.request.Request(
                    f"{base_url.rstrip('/')}/responses",
                    data=json.dumps(payload).encode("utf-8"),
                    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                )
                with urllib.request.urlopen(req, timeout=timeout) as response:
                    data = json.loads(response.read().decode("utf-8"))
                content = data.get("output_text") or ""
                if not content:
                    output = data.get("output") or []
                    if output:
                        first = output[0]
                        content_items = first.get("content") or []
                        if content_items:
                            content = content_items[0].get("text", "") or ""
                if not content:
                    content = "AI advisory returned no content."
            except asyncio.CancelledError:
                content = "AI advisory cancelled."
                exit_code = 130
                raise
            except (socket.timeout, urllib.error.URLError):
                content = (
                    "AI advisory timed out or could not reach the network. "
                    "Check connectivity and OPENAI_* settings, then retry."
                )
                exit_code = 1
            except Exception:
                content = (
                    "AI advisory failed. Verify OPENAI_* settings and try again."
                )
                exit_code = 1
            finally:
                output_widget.text = content
                safe_write_text(run_dir / "output.log", content)
                now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                write_metadata(run_dir, "cleanup", "analysis", "ai_advisory", exit_code, now, now, self.cwd)

        task = asyncio.create_task(call_api())
        self.track_task(task)

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "observe-filter":
            self.refresh_observe()

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "cleanup-file":
            self.load_cleanup_file()
        elif event.input.id == "observe-filter":
            self.refresh_observe()
        elif event.input.id == "files-path":
            self.open_path_from_input()
        elif event.input.id == "terminal-command":
            await self.run_terminal_command()


if __name__ == "__main__":
    disable_textual_mouse()
    app = OverwatchApp()
    app.run()
PY
  python3 "${TEMP_PY_FILE}"
fi
