#!/usr/bin/env bash
# Behavior test for format-events.jq and watch.sh. Run: bash account-delegate/tests/test_watch.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
FIX="$HERE/fixtures/events.jsonl"
# character counts below assume a UTF-8 locale; en_US.UTF-8 is not installed everywhere (Linux)
if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then export LC_ALL=en_US.UTF-8; else export LC_ALL=C.UTF-8; fi
fail=0
check() { # $1 = description, then a command that must succeed
  local d="$1"; shift
  if "$@"; then echo "ok: $d"; else echo "FAIL: $d"; fail=1; fi
}

OUT="$(jq -R -r -f "$SCRIPTS/format-events.jq" < "$FIX")"
check "init line shows model and cwd" grep -qF '● started · model: fake-model · cwd: /tmp/proj' <<<"$OUT"
check "assistant text is flattened to one line" grep -qF '· Looking at the code' <<<"$OUT"
check "tool use shows tool and file path" grep -qF '→ Read /tmp/proj/a.kt' <<<"$OUT"
check "tool use shows grep pattern" grep -qF '→ Grep TODO' <<<"$OUT"
check "denied tool result is shown" grep -qF '✗ Permission to use Bash has been denied.' <<<"$OUT"
check "successful tool result is hidden" bash -c '! grep -qx "✗ ok" <<<"$1"' _ "$OUT"
check "garbage line is skipped and later lines still render" grep -qF '→ Grep TODO' <<<"$OUT"
check "result line shows subtype, turns and cost" grep -qF '■ finished · success · turns: 3 · cost: $0.42' <<<"$OUT"

LONG="$(printf 'x%.0s' $(seq 1 300))"
CLIP="$(printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$LONG" | jq -R -r -f "$SCRIPTS/format-events.jq")"
check "long text is clipped to 200 chars plus ellipsis" test "${#CLIP}" -eq 203

JOB="$(mktemp -d)"
( sleep 1; cp "$FIX" "$JOB/events.jsonl"; sleep 1
  printf '%s' '{"exit_code":0,"is_error":false,"subtype":"success","num_turns":3,"total_cost_usd":0.42}' > "$JOB/meta.json" ) &
WOUT="$(perl -e 'alarm 15; exec @ARGV' bash "$SCRIPTS/watch.sh" "$JOB")"; wcode=$?
check "watch exits 0 once meta.json appears" test "$wcode" -eq 0
check "watch renders events that arrive later" grep -qF '→ Read /tmp/proj/a.kt' <<<"$WOUT"
check "watch prints the summary" grep -qF 'job finished · exit 0 · error: false · success · turns: 3 · cost: $0.42' <<<"$WOUT"
rm -rf "$JOB"

JOB="$(mktemp -d)"
printf '%s' '{"exit_code":143,"is_error":true,"subtype":null,"num_turns":null,"total_cost_usd":null}' > "$JOB/meta.json"
WOUT="$(perl -e 'alarm 10; exec @ARGV' bash "$SCRIPTS/watch.sh" "$JOB")"; wcode=$?
check "watch exits when the job died before any events" test "$wcode" -eq 0
check "watch summary handles missing fields" grep -qF 'job finished · exit 143 · error: true' <<<"$WOUT"
rm -rf "$JOB"

JOB="$(mktemp -d)"
sleep 30 & DEAD=$!; echo "$DEAD" > "$JOB/pid"; kill "$DEAD"; wait "$DEAD" 2>/dev/null
cp "$FIX" "$JOB/events.jsonl"
WOUT="$(perl -e 'alarm 10; exec @ARGV' bash "$SCRIPTS/watch.sh" "$JOB")"; wcode=$?
check "watch exits 1 when the job process is gone without meta.json" test "$wcode" -eq 1
check "watch explains the missing meta.json" grep -qF 'job process is gone without meta.json' <<<"$WOUT"
check "watch still renders the events it had" grep -qF '→ Read /tmp/proj/a.kt' <<<"$WOUT"

JOB="$(mktemp -d)"
( sleep 1; printf '%s' '{"exit_code":0,"is_error":false}' > "$JOB/meta.json" ) &
echo $$ > "$JOB/pid"   # a live pid: keep waiting for meta.json
WOUT="$(perl -e 'alarm 10; exec @ARGV' bash "$SCRIPTS/watch.sh" "$JOB")"; wcode=$?
check "watch keeps waiting while the job process is alive" test "$wcode" -eq 0
rm -rf "$JOB"
exit $fail
