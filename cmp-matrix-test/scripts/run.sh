#!/usr/bin/env bash
# Runs the private cmpose.dev backend's smoke gate (`npm run smoke`) and keeps a copy of its output.
# Usage: run.sh [--ref <tag|branch> | --dir <template dir>] [--build-only]
# Env:   CMP_BACKEND_DIR (REQUIRED: your cmpose.dev backend checkout)
set -u
B=${CMP_BACKEND_DIR:-}
if [ -z "$B" ]; then
  echo "ERROR: CMP_BACKEND_DIR is not set — set it to your cmpose.dev backend checkout (e.g. in your shell profile)"
  exit 2
fi
if [ ! -f "$B/package.json" ] || ! grep -q '"smoke"' "$B/package.json"; then
  echo "ERROR: no cmpose.dev backend with an npm 'smoke' script at $B (set CMP_BACKEND_DIR)"
  exit 2
fi
mkdir -p "$HOME/cmp-verify"
LOG="$HOME/cmp-verify/cmp-matrix-test-$(date +%Y%m%d-%H%M%S).log"
echo "log: $LOG"
cd "$B" && npm run smoke -- "$@" 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"
