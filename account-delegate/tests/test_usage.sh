#!/usr/bin/env bash
# Behavior test for usage.sh. Run: bash account-delegate/tests/test_usage.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
USAGE="$HERE/../scripts/usage.sh"
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok: $d"; else echo "FAIL: $d"; fail=1; fi; }

TMP="$(mktemp -d)"
export DELEGATE_CACHE_DIR="$TMP/cache" USAGE_MAIN_PROJECTS_DIR="$TMP/projects"
job() { # $1 = job dir, $2 = started_at, $3 = cost, $4 = output tokens
  mkdir -p "$1"
  printf '{"started_at":"%s"}\n' "$2" > "$1/meta.json"
  printf '%s\n' '{"type":"system","subtype":"init"}' \
    "{\"type\":\"result\",\"total_cost_usd\":$3,\"usage\":{\"input_tokens\":1,\"output_tokens\":$4,\"cache_read_input_tokens\":100,\"cache_creation_input_tokens\":10}}" \
    > "$1/events.jsonl"
}
job "$TMP/cache/20261005-100000-abcd" 2026-10-05T10:00:00Z 0.5 1000
job "$TMP/cache/plans/p-kermit/jobs/1" 2026-10-05T11:00:00Z 1.25 2000
job "$TMP/cache/plans/p-kermit/jobs/2" 2026-10-05T12:00:00Z 0.25 500
job "$TMP/cache/old-job" 2026-09-01T00:00:00Z 9 9000
mkdir -p "$TMP/cache/broken" && echo 'not json' > "$TMP/cache/broken/events.jsonl"
job "$TMP/cache/plans/p-kermit/worktree/tests/fixtures" 2026-10-05T12:00:00Z 7 7000   # a file in a job's tree, not a job

mkdir -p "$TMP/projects/-Users-x-projA/sub" "$TMP/projects/-Users-x-projB"
msg() { printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","model":"m","usage":{"input_tokens":2,"output_tokens":%s,"cache_read_input_tokens":1000,"cache_creation_input_tokens":50}}}\n' "$1" "$2" "$3"; }
{ msg 2026-10-05T09:00:00Z a1 100; msg 2026-10-05T09:00:00Z a1 100; echo 'garbage'; msg 2026-09-01T00:00:00Z old 999; } > "$TMP/projects/-Users-x-projA/s.jsonl"
msg 2026-10-05T09:05:00Z a2 300 > "$TMP/projects/-Users-x-projA/sub/agent.jsonl"
msg 2026-10-06T08:00:00Z b1 50 > "$TMP/projects/-Users-x-projB/t.jsonl"

OUT="$(bash "$USAGE" --since 2026-10-05 2>"$TMP/err")"; CODE=$?
check "exits 0" test "$CODE" -eq 0
check "plan row: 2 jobs, cost and output summed" grep -qE '^p-kermit +2 +\$1\.50 +2500 ' <<<"$OUT"
check "single jobs grouped" grep -qE '^single jobs +1 +\$0\.50 +1000 ' <<<"$OUT"
check "second account total excludes jobs before --since" grep -qE '^TOTAL +3 +\$2\.00 +3500 ' <<<"$OUT"
check "unreadable job is skipped" bash -c '! grep -q broken <<<"$1"' _ "$OUT"
check "main project row: duplicate message counted once, subagent file included" grep -qE '^-Users-x-projA +2 +400 ' <<<"$OUT"
check "main total excludes messages before --since" grep -qE '^TOTAL +3 +450 ' <<<"$OUT"

OUT="$(bash "$USAGE" --since 2026-10-06)"
check "--since filters by day" grep -qE '^TOTAL +1 +50 ' <<<"$OUT"
bash "$USAGE" --since yesterday >/dev/null 2>&1; check "bad --since exits 2" test $? -eq 2
bash "$USAGE" --bogus >/dev/null 2>&1; check "unknown flag exits 2" test $? -eq 2
OUT="$(DELEGATE_CACHE_DIR="$TMP/none" USAGE_MAIN_PROJECTS_DIR="$TMP/none" bash "$USAGE" --since 2026-10-05)"
check "missing dirs: still exits 0 with zero totals" bash -c 'test "$1" -eq 0 && grep -qE "^TOTAL +0 +\\\$0\.00 +0 " <<<"$2"' _ $? "$OUT"

rm -rf "$TMP"
exit $fail
