#!/usr/bin/env bash
# One call that returns the LIVE backend state the skill needs before generating:
# config (limits), versions (libs/jdk), and rate-limit status — merged into one JSON,
# plus contractCurrent (true/false/null: does the skill's contract.json match the server's contractVersion).
# No jq/node required: the API already returns JSON, so we splice the raw objects in.
#
# Usage: preflight.sh
# Endpoint: env CMP_API > defaults.json.apiBase > https://cmpose.dev
# Always prints a JSON object to stdout; "reachable" is false if /api/config failed.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULTS="$SKILL_DIR/defaults.json"

API="${CMP_API:-}"
if [ -z "$API" ] && [ -f "$DEFAULTS" ]; then
  API="$(grep -oE '"apiBase"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEFAULTS" 2>/dev/null \
        | sed -E 's/.*"apiBase"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' | head -1)"
fi
API="${API:-https://cmpose.dev}"
API="${API%/}"   # drop trailing slash

fetch() { # $1=path → echoes body on HTTP 200, returns 1 otherwise
  local tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -o "$tmp" -w '%{http_code}' --max-time 15 "$API$1" 2>/dev/null || echo 000)"
  if [ "$code" = "200" ] && [ -s "$tmp" ]; then cat "$tmp"; rm -f "$tmp"; return 0; fi
  rm -f "$tmp"; return 1
}

CFG="$(fetch /api/config)" && REACHABLE=true || { CFG=null; REACHABLE=false; }
VER="$(fetch /api/versions)"          || VER=null
RL="$(fetch /api/rate-limit-status)"  || RL=null

# Is this skill's committed contract the server's current one? true / false / null (unknown)
CONTRACT="$SKILL_DIR/reference/contract.json"
pick_version() { grep -oE '"contractVersion"[[:space:]]*:[[:space:]]*"[0-9a-f]+"' | head -1 | sed -E 's/.*"([0-9a-f]+)"$/\1/'; }
LIVE_V="$(printf '%s' "$CFG" | pick_version)"
LOCAL_V="$( [ -f "$CONTRACT" ] && pick_version < "$CONTRACT" )"
if [ -z "$LIVE_V" ] || [ -z "$LOCAL_V" ]; then CURRENT=null
elif [ "$LIVE_V" = "$LOCAL_V" ]; then CURRENT=true; else CURRENT=false; fi

printf '{"apiBase":"%s","reachable":%s,"config":%s,"versions":%s,"rateLimit":%s,"contractCurrent":%s}\n' \
  "$API" "$REACHABLE" "${CFG:-null}" "${VER:-null}" "${RL:-null}" "$CURRENT"

[ "$REACHABLE" = true ] || exit 1
