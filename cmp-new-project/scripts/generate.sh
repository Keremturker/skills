#!/usr/bin/env bash
# POST a payload to cmpose.dev /api/generate, download + extract the project zip.
# Usage: generate.sh <payload.json> <outputDir> <projectName>
# Endpoint: env CMP_API > defaults.json.apiBase > https://cmpose.dev
# Exit: 0 ok · 2 rate-limit(429) · 3 validation(400) · 4 payload-too-large(413) · 5 busy(503) · 1 other/network
set -euo pipefail

PAYLOAD="${1:?payload json path required}"
OUT="${2:?output dir required}"
NAME="${3:?project name required}"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULTS="$SKILL_DIR/defaults.json"
API="${CMP_API:-}"
if [ -z "$API" ] && [ -f "$DEFAULTS" ]; then
  API="$(grep -oE '"apiBase"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEFAULTS" 2>/dev/null \
        | sed -E 's/.*"apiBase"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' | head -1)"
fi
API="${API:-https://cmpose.dev}"
API="${API%/}"

mkdir -p "$OUT"
TMP="$(mktemp -t cmpgen).bin"
trap 'rm -f "$TMP"' EXIT

CODE=$(curl -sS -X POST "$API/api/generate" \
  -H 'Content-Type: application/json' \
  --data-binary @"$PAYLOAD" \
  -o "$TMP" -w '%{http_code}' --max-time 240 || echo "000")

case "$CODE" in
  200)
    if ! unzip -tq "$TMP" >/dev/null 2>&1; then
      echo "ERROR: HTTP 200 but the response is not a valid zip:"
      head -c 400 "$TMP"; echo; exit 1
    fi
    unzip -o -q "$TMP" -d "$OUT"
    echo "OK: extracted to $OUT/$NAME"
    ;;
  429)  echo "RATE_LIMIT: $(cat "$TMP")"; exit 2 ;;
  400)  echo "VALIDATION: $(cat "$TMP")"; exit 3 ;;
  413)  echo "PAYLOAD_TOO_LARGE: body over the server limit (usually a large detektYamlContent). $(cat "$TMP")"; exit 4 ;;
  503)  echo "BUSY: server at its concurrent-generation limit, no quota spent. $(cat "$TMP")"; exit 5 ;;
  000)  echo "NETWORK_ERROR: could not reach $API/api/generate"; exit 1 ;;
  *)    echo "ERROR (HTTP $CODE): $(cat "$TMP")"; exit 1 ;;
esac
