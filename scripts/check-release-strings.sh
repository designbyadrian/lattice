#!/usr/bin/env bash
# Fails a release binary if it still contains debug/local markers.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <path-to-binary>" >&2
  exit 2
fi

BIN="$1"
if [[ ! -f "$BIN" ]]; then
  echo "error: not a file: $BIN" >&2
  exit 2
fi

PATTERNS=(
  'localhost'
  '127.0.0.1'
  '/Users/'
  'ENABLE_DEBUG'
  'LatticeDebugOnly'
)

FAILED=0
for pat in "${PATTERNS[@]}"; do
  if strings "$BIN" | grep -F "$pat" >/dev/null 2>&1; then
    echo "FAIL: found forbidden string '$pat' in $BIN" >&2
    FAILED=1
  fi
done

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi

echo "OK: no forbidden release strings in $BIN"
