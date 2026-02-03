#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
artifact_compress — build a clean zip artifact
Usage: artifact_compress output.zip [path]
Defaults:
  output.zip = project.zip
  path       = .
EOF
}

OUT="${1:-project.zip}"
TARGET="${2:-.}"
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

cd "$TARGET" 2>/dev/null || { echo "artifact_compress: cannot cd into: $TARGET" >&2; exit 1; }

command -v zip >/dev/null 2>&1 || { echo "artifact_compress: zip not found" >&2; exit 1; }

echo "== ARTIFACT_COMPRESS: BUILDING $OUT =="
zip -r "$OUT" . \
  -x "*.git*" "*__pycache__*" "*.pytest_cache*" "*.venv*" \
     "*node_modules*" "*dist*" "*build*" "*.ruff_cache*" "*.mypy_cache*"
echo "Done: $(pwd)/$OUT"
