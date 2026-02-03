#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
chronos_probe — environment fingerprint (OS/arch/python/tooling)
Usage: chronos_probe
EOF
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

echo "== CHRONOS_PROBE: ENV FINGERPRINT =="
echo "Kernel: $(uname -a)"
echo "Arch:   $(uname -m)"
echo "Shell:  ${SHELL:-unknown}"
echo "PWD:    $(pwd)"
echo

if command -v python3 >/dev/null 2>&1; then
  echo "Python: $(python3 --version)"
else
  echo "Python: not found"
fi

if command -v git >/dev/null 2>&1; then
  echo "Git:    $(git --version)"
else
  echo "Git:    not found"
fi

if command -v apt >/dev/null 2>&1; then
  echo "Pkg:    apt"
elif command -v pkg >/dev/null 2>&1; then
  echo "Pkg:    pkg (Termux)"
elif command -v dnf >/dev/null 2>&1; then
  echo "Pkg:    dnf"
elif command -v pacman >/dev/null 2>&1; then
  echo "Pkg:    pacman"
else
  echo "Pkg:    unknown"
fi
