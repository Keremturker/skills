#!/usr/bin/env bash
# Live view of a delegated job. Usage: watch.sh <job dir>
# Prints events as they arrive and exits once meta.json exists.
set -u
JOB="${1:?usage: watch.sh <job dir>}"
FMT="$(cd "$(dirname "$0")" && pwd)/format-events.jq"
EVENTS="$JOB/events.jsonl"
shown=0

show_new() { # print complete lines added since the last call
  [ -e "$EVENTS" ] || return 0
  local total
  total=$(wc -l < "$EVENTS" | tr -d ' ')
  if [ "$total" -gt "$shown" ]; then
    sed -n "$((shown + 1)),${total}p" "$EVENTS" | jq -R -r -f "$FMT"
    shown=$total
  fi
}

echo "account-delegate · $(basename "$JOB")"
while [ ! -e "$JOB/meta.json" ]; do
  show_new
  sleep 0.5
done
show_new
echo
jq -r '"job finished · exit \(.exit_code) · error: \(.is_error)"
  + (if .subtype then " · \(.subtype)" else "" end)
  + (if .num_turns then " · turns: \(.num_turns)" else "" end)
  + (if .total_cost_usd then " · cost: $\(.total_cost_usd)" else "" end)' "$JOB/meta.json"
