#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# Overwatch: Sentinel / Night Ops
# Self-contained cross-platform TUI cockpit
# - Left: modes (Observe / Files / Operate / Cleanup / Config / About)
# - Right: persistent terminal pane (always visible)
# - Global cwd shared across Files/Operate/Terminal
# - Runs logging: runs/<ts>_<mode>_<action>/{output.log,metadata.json}
# -------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
COCKPIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${COCKPIT_DIR}/.." && pwd -P)"

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
  restore_terminal
  jobs -p | xargs kill -9 2>/dev/null || true
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

run_fallback_mode() {
  echo "Textual not available. Running fallback mode."
  echo "Platform: ${PLATFORM}"
  echo "Tip: install Textual with: ${PYTHON_CMD} -m pip install textual"
  echo ""

  while true; do
    echo ""
    echo "OVERWATCH (Fallback)"
    echo "1) List runs"
    echo "2) List locker tools"
    echo "3) Run command in repo root"
    echo "q) Quit"
    printf "> "
    read -r sel
    case "${sel:-}" in
      1)
        ls -1t "${RUNS_DIR}" 2>/dev/null | head -n 30 || echo "No runs yet."
        ;;
      2)
        if [ -d "${LOCKER_DIR}" ]; then
          ls -1 "${LOCKER_DIR}"/*.sh 2>/dev/null | sed 's#.*/##' || echo "No tools."
        else
          echo "No locker directory at ${LOCKER_DIR}"
        fi
        ;;
      3)
        printf "cmd> "
        read -r cmd
        [ -z "${cmd}" ] && continue
        (cd "${REPO_ROOT}" && bash -lc "${cmd}")
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
  disable_mouse_reporting

  # We must NOT use: python3 - <<PY (would steal stdin).
  # Prefer /dev/fd/63 on unix.
  if [ -r /dev/fd/63 ] 2>/dev/null; then
    exec "${PYTHON_CMD}" /dev/fd/63 63< <(cat <<PY
import asyncio
import json
import os
import platform as _platform
import shlex
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple

CURRENT_PLATFORM = "${PLATFORM}"

SCRIPT_DIR = Path("${SCRIPT_DIR}").resolve()
COCKPIT_DIR = Path("${COCKPIT_DIR}").resolve()
REPO_ROOT = Path("${REPO_ROOT}").resolve()
RUNS_DIR = Path("${RUNS_DIR}").resolve()
CONFIG_DIR = Path("${CONFIG_DIR}").resolve()
ENV_FILE = Path("${ENV_FILE}").resolve()
LOCKER_DIR = Path("${LOCKER_DIR}").resolve()

RUNS_DIR.mkdir(parents=True, exist_ok=True)

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

def list_dir_entries(cwd: Path) -> Tuple[list, str]:
    try:
        entries = list(cwd.iterdir())
    except Exception as e:
        return [], f"Cannot list directory: {e}"
    dirs = sorted([p for p in entries if p.is_dir()], key=lambda p: p.name.lower())
    files = sorted([p for p in entries if p.is_file()], key=lambda p: p.name.lower())
    return dirs + files, ""

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widgets import Footer, Input, Label, ListItem, ListView, Static, TextArea

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
        t = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        return f"MODE: {self.mode} | {CURRENT_PLATFORM} | CWD: {self.cwd} | {t} | {self.ai}"

class NavItem(ListItem):
    def __init__(self, label: str, tag: str = ""):
        super().__init__(Label(label))
        self.label_text = label
        self.tag = tag or label

class ObservePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Recent Runs")
        yield ListView(id="observe-list")
        yield TextArea(id="observe-output", read_only=True)

class FilesPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Filesystem Navigator")
        yield Label("Enter: open dir / preview file | '..' = parent", id="files-hint")
        yield Label("CWD:", id="files-cwd")
        yield Input(placeholder="Type a path and press Enter", id="files-path")
        yield ListView(id="files-list")
        yield TextArea(id="files-preview", read_only=True)

class OperatePane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Locker Tools")
        yield ListView(id="operate-list")
        yield Input(placeholder="Arguments", id="operate-args")
        yield TextArea(id="operate-preview", read_only=True)

class CleanupPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Cleanup (notes + analysis placeholder)")
        yield TextArea(id="cleanup-input")
        yield TextArea(id="cleanup-analysis", read_only=True)

class ConfigPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Config Status")
        yield TextArea(id="config-text", read_only=True)

class AboutPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("OVERWATCH: SENTINEL / NIGHT OPS")
        yield TextArea(
            "Mission terminal for JADIS Arsenal operations.\n"
            "Left pane: modes. Right pane: persistent terminal.\n"
            "Safety: confirmations for destructive commands.\n",
            read_only=True,
        )

class TerminalPane(Static):
    def compose(self) -> ComposeResult:
        yield Label("Terminal", id="term-title")
        yield Label("", id="term-cwd")
        yield Input(placeholder="Command (press Enter to run)", id="term-cmd")
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
    }}
    #body {{
        height: 1fr;
    }}
    #left {{
        width: 1fr;
        min-width: 60;
        border: solid {BORDER};
        background: {PANEL};
    }}
    #right {{
        width: 60;
        min-width: 48;
        border: solid {BORDER};
        background: {PANEL};
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
    Input:focus, TextArea:focus {{
        border: solid {ACCENT};
    }}
    #files-hint {{
        color: {ACCENT_DIM};
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
        Binding("enter", "enter", "Enter"),
        Binding("r", "refresh", "Refresh"),
        Binding("?", "help", "Help"),
    ]

    mode = reactive("Observe")

    def __init__(self):
        super().__init__()
        self.cwd = REPO_ROOT
        self._running_proc: Optional[asyncio.subprocess.Process] = None
        self._running_task: Optional[asyncio.Task] = None
        self.nav_map = ["Observe", "Files", "Operate", "Cleanup", "Config", "About"]

    def compose(self) -> ComposeResult:
        with Vertical(id="root"):
            yield StatusHeader(id="header")
            with Horizontal(id="body"):
                with Vertical(id="left"):
                    yield ListView(id="nav")
                    with Container(id="main"):
                        self.observe = ObservePane(id="observe-pane")
                        self.files = FilesPane(id="files-pane")
                        self.operate = OperatePane(id="operate-pane")
                        self.cleanup = CleanupPane(id="cleanup-pane")
                        self.config = ConfigPane(id="config-pane")
                        self.about = AboutPane(id="about-pane")
                        yield self.observe
                        yield self.files
                        yield self.operate
                        yield self.cleanup
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
        self.update_cwd_labels()
        self.switch_mode("Observe")
        self.refresh_all()
        nav.focus()

    def update_ai_status(self) -> None:
        env = load_env_file(ENV_FILE)
        key_ok = bool(env.get("OPENAI_API_KEY", "").strip())
        model = env.get("OPENAI_MODEL", "").strip()
        hdr = self.query_one(StatusHeader)
        hdr.ai = f"AI: {model}" if (key_ok and model) else "AI: unavailable"

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
        self.cleanup.display = (name == "Cleanup")
        self.config.display = (name == "Config")
        self.about.display = (name == "About")

    def action_back(self) -> None:
        self.query_one("#nav", ListView).focus()

    def action_search(self) -> None:
        if self.mode == "Files":
            self.query_one("#files-path", Input).focus()

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
        lv = self.query_one("#files-list", ListView)
        lv.clear()
        lv.append(NavItem(".. (parent)", tag="__parent__"))
        entries, err = list_dir_entries(self.cwd)
        preview = self.query_one("#files-preview", TextArea)
        if err:
            preview.text = err + "\n"
            return

        for p in entries:
            if p.is_dir():
                lv.append(NavItem(p.name + "/", tag=str(p)))
        for p in entries:
            if p.is_file():
                lv.append(NavItem(p.name, tag=str(p)))
        lv.index = 0
        preview.text = "Select an entry and press Enter.\n"

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
            content = p.read_text(errors="ignore")
            body = content[:6000] + ("\n\n...[truncated]...\n" if len(content) > 6000 else "")
            return head + body
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
        env = load_env_file(ENV_FILE)
        lines = [f"Config file: {ENV_FILE}\n"]
        lines.append(f"OPENAI_API_KEY: {'set' if env.get('OPENAI_API_KEY') else 'not set'}\n")
        lines.append(f"OPENAI_MODEL: {env.get('OPENAI_MODEL','not set') or 'not set'}\n")
        self.query_one("#config-text", TextArea).text = "".join(lines)

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id == "nav":
            item = event.item
            if isinstance(item, NavItem):
                self.switch_mode(item.label_text)
                self.update_cwd_labels()
        elif event.list_view.id == "observe-list":
            self.open_selected_run()
        elif event.list_view.id == "files-list":
            item = event.item
            if not isinstance(item, NavItem):
                return
            prev = self.query_one("#files-preview", TextArea)
            if item.tag == "__parent__":
                prev.text = f"Go to parent of {self.cwd}\n"
            else:
                prev.text = self.preview_path(Path(item.tag))
        elif event.list_view.id == "operate-list":
            item = event.item
            if not isinstance(item, NavItem) or item.tag == "__empty__":
                return
            tool = Path(item.tag)
            args = self.query_one("#operate-args", Input).value.strip()
            cmd = f"{tool} {args}".strip()
            self.query_one("#operate-preview", TextArea).text = f"CWD: {self.cwd}\nPreview: {cmd}\n"

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
                self.query_one("#files-list", ListView).focus()
            else:
                self.query_one("#files-preview", TextArea).text = f"Invalid directory: {raw}\n"
        elif event.input.id == "term-cmd":
            cmd = event.value.strip()
            if not cmd:
                return
            event.input.value = ""
            asyncio.create_task(self.run_terminal_command(cmd))

    async def action_enter(self) -> None:
        focused = self.focused
        if self.mode == "Files" and isinstance(focused, ListView) and focused.id == "files-list":
            await self.files_enter()
        elif self.mode == "Operate" and isinstance(focused, ListView) and focused.id == "operate-list":
            await self.operate_enter()
        elif self.mode == "Observe" and isinstance(focused, ListView) and focused.id == "observe-list":
            self.open_selected_run()

    async def files_enter(self) -> None:
        lv = self.query_one("#files-list", ListView)
        if lv.index is None:
            return
        item = lv.get_item_at(lv.index)
        if not isinstance(item, NavItem):
            return
        prev = self.query_one("#files-preview", TextArea)
        if item.tag == "__parent__":
            parent = self.cwd.parent if self.cwd.parent != self.cwd else self.cwd
            try:
                _ = list(parent.iterdir())
                self.cwd = parent
                self.update_cwd_labels()
                self.refresh_files()
            except Exception as e:
                prev.text = f"Cannot enter parent: {e}\n"
            return
        p = Path(item.tag)
        if p.is_dir():
            try:
                _ = list(p.iterdir())
                self.cwd = p
                self.update_cwd_labels()
                self.refresh_files()
            except Exception as e:
                prev.text = f"Cannot enter directory: {e}\n"
        else:
            prev.text = self.preview_path(p)

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
)"
  else
    # mktemp fallback stub
    tmp="${TMPDIR:-/tmp}/overwatch_$$.py"
    cat > "${tmp}" <<'PY'
print("overwatch.sh: mktemp fallback stub was triggered, but this distribution expects /dev/fd/63.")
print("If you're seeing this, tell me your platform and shell (bash/zsh/pwsh).")
raise SystemExit(1)
PY
    "${PYTHON_CMD}" "${tmp}"
    rm -f "${tmp}" 2>/dev/null || true
    exit 1
  fi
}

main() {
  check_python
  check_textual
  echo "Starting Overwatch (Platform: ${PLATFORM})..."
  run_python_app
}

main "$@"
