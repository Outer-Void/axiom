#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
pulsecheck — quick system resource snapshot
Usage: pulsecheck
EOF
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

echo "== PULSECHECK: SYSTEM STATE =="
if command -v nproc >/dev/null 2>&1; then
  echo "CPU cores: $(nproc)"
else
  echo "CPU cores: n/a"
fi

if command -v free >/dev/null 2>&1; then
  echo "Memory: $(free -h | awk '/Mem:/ {print $3 \" used / \" $2 \" total\"}')"
elif command -v vm_stat >/dev/null 2>&1; then
  echo "Memory: (vm_stat available; macOS style)"
  vm_stat | head -n 8
else
  echo "Memory: n/a"
fi

if command -v df >/dev/null 2>&1; then
  echo "Disk (/): $(df -h / | awk 'NR==2 {print $4 \" free / \" $2 \" total\"}')"
else
  echo "Disk: n/a"
fi
