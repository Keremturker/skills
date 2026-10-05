#!/usr/bin/env bash
# Behavior test for delegate.sh (uses tests/fake-claude.sh, never the real CLI).
# Run: bash account-delegate/tests/test_delegate.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
DELEGATE="$HERE/../scripts/delegate.sh"
fail=0
check() { # $1 = description, then a command that must succeed
  local d="$1"; shift
  if "$@"; then echo "ok: $d"; else echo "FAIL: $d"; fail=1; fi
}
has_arg() { grep -qxF -- "$1" "$FAKE_LOG/args"; }
lacks_arg() { ! grep -qF -- "$1" "$FAKE_LOG/args"; }
meta() { jq -r "$1" "$JOB/meta.json"; }

TMP="$(mktemp -d)"
export DELEGATE_CLAUDE_BIN="$HERE/fake-claude.sh"
export DELEGATE_CLAUDE_CONFIG_DIR="$TMP/second-account"
export DELEGATE_CACHE_DIR="$TMP/cache"
export FAKE_LOG="$TMP/log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$DELEGATE_CLAUDE_CONFIG_DIR" "$FAKE_LOG" "$TMP/proj"
printf 'Analyse the module.\n' > "$TMP/brief.md"

run() { # runs delegate.sh, sets OUT, CODE, JOB
  OUT="$(bash "$DELEGATE" "$@" 2>"$TMP/err")"; CODE=$?
  JOB="$(sed -n 's/^JOB_DIR=//p' <<<"$OUT" | head -n 1)"
}

# --- usage errors
run; check "no args exits 2" test "$CODE" -eq 2
run --mode nope --cwd "$TMP/proj" --brief "$TMP/brief.md"; check "bad mode exits 2" test "$CODE" -eq 2
run --mode ro --cwd "$TMP/missing" --brief "$TMP/brief.md"; check "missing cwd exits 2" test "$CODE" -eq 2
run --mode ro --cwd "$TMP/proj" --brief "$TMP/none.md"; check "missing brief exits 2" test "$CODE" -eq 2
: > "$TMP/empty.md"
run --mode ro --cwd "$TMP/proj" --brief "$TMP/empty.md"; check "empty brief exits 2" test "$CODE" -eq 2
run --mode ro --cwd "$TMP/proj" --brief; check "flag without value exits 2" test "$CODE" -eq 2
DELEGATE_CLAUDE_CONFIG_DIR="$TMP/nowhere" run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "missing second-account config exits 2" test "$CODE" -eq 2
DELEGATE_CLAUDE_BIN="$TMP/no-claude" run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "missing claude binary exits 2" test "$CODE" -eq 2
DELEGATE_MAX_TURNS=abc run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "non-numeric max turns exits 2" test "$CODE" -eq 2
run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --id '../evil'
check "id with a slash exits 2" test "$CODE" -eq 2

# --- read-only success
export CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_CODE_SESSION_ID=parent ANTHROPIC_API_KEY=sk-personal
export CLAUDE_CODE_FOO=1 CLAUDE_CODE_OAUTH_TOKEN=x ANTHROPIC_AUTH_TOKEN=t ANTHROPIC_BASE_URL=http://x ANTHROPIC_MODEL=m
export ANTHROPIC_CUSTOM_HEADERS='X-A: b' ANTHROPIC_SMALL_FAST_MODEL=s
FAKE_MODE=ok run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID ANTHROPIC_API_KEY CLAUDE_CODE_FOO CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL
unset ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_SMALL_FAST_MODEL
check "ro run exits 0" test "$CODE" -eq 0
check "first stdout line is JOB_DIR=" bash -c 'head -n 1 <<<"$1" | grep -q "^JOB_DIR=/"' _ "$OUT"
check "job id has the documented format" bash -c 'basename "$1" | grep -Eq "^[0-9]{8}-[0-9]{6}-[a-z0-9]{4}$"' _ "$JOB"
check "brief is copied into the job dir" cmp -s "$TMP/brief.md" "$JOB/brief.md"
check "brief is sent on stdin" cmp -s "$TMP/brief.md" "$FAKE_LOG/stdin"
check "events.jsonl holds the stream" grep -q '"type":"result"' "$JOB/events.jsonl"
check "result.md holds the final report" grep -qx 'All done.' "$JOB/result.md"
check "CLAUDE_CONFIG_DIR points at the second account" grep -qxF "$DELEGATE_CLAUDE_CONFIG_DIR" "$FAKE_LOG/config"
check "runs in --cwd" test "$(cat "$FAKE_LOG/pwd")" = "$(cd "$TMP/proj" && pwd -P)"
check "env isolation: CLAUDECODE unset" bash -c '! grep -q "^CLAUDECODE=" "$1"' _ "$FAKE_LOG/env"
check "env isolation: CLAUDE_CODE_* unset" bash -c '! grep -q "^CLAUDE_CODE_" "$1"' _ "$FAKE_LOG/env"
check "env isolation: ANTHROPIC_API_KEY unset" bash -c '! grep -q "^ANTHROPIC_API_KEY=" "$1"' _ "$FAKE_LOG/env"
check "env isolation: no ANTHROPIC_* at all" bash -c '! grep -q "^ANTHROPIC_" "$1"' _ "$FAKE_LOG/env"
for v in CLAUDE_CODE_FOO CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_SMALL_FAST_MODEL; do
  check "env isolation: $v unset" bash -c '! grep -q "^$2=" "$1"' _ "$FAKE_LOG/env" "$v"
done
check "headless flag" has_arg -p
check "stream-json output" has_arg stream-json
check "verbose (required by stream-json)" has_arg --verbose
check "default max turns is 40" bash -c 'grep -A1 -xF -- --max-turns "$1" | tail -n 1 | grep -qx 40' _ "$FAKE_LOG/args"
check "report instructions appended" has_arg --append-system-prompt
check "ro permission mode is default" bash -c 'grep -A1 -xF -- --permission-mode "$1" | tail -n 1 | grep -qx default' _ "$FAKE_LOG/args"
check "ro allowed tools" has_arg 'Read,Grep,Glob,WebSearch,WebFetch'
check "ro disallowed tools include Bash and edits" has_arg 'Edit,Write,NotebookEdit,Bash'
for f in --mcp-config --plugin-dir --agents --dangerously-skip-permissions bypassPermissions; do
  check "never passes $f" lacks_arg "$f"
done
check "meta mode" test "$(meta .mode)" = ro
check "meta is_error false" test "$(meta .is_error)" = false
check "meta exit_code 0" test "$(meta .exit_code)" = 0
check "meta subtype" test "$(meta .subtype)" = success
check "meta num_turns" test "$(meta .num_turns)" = 2
check "meta cost" test "$(meta .total_cost_usd)" = 0.3
check "meta session_id" test "$(meta .session_id)" = s1
check "meta worktree null in ro" test "$(meta .worktree)" = null
check "meta branch null in ro" test "$(meta .branch)" = null
check "meta start_branch null in ro" bash -c 'jq -e "has(\"start_branch\") and .start_branch == null" "$1" >/dev/null' _ "$JOB/meta.json"
check "meta timestamps" bash -c 'jq -e ".started_at and .finished_at" "$1" >/dev/null' _ "$JOB/meta.json"

# --- options
DELEGATE_MAX_TURNS=5 FAKE_MODE=ok run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "DELEGATE_MAX_TURNS is honoured" bash -c 'grep -A1 -xF -- --max-turns "$1" | tail -n 1 | grep -qx 5' _ "$FAKE_LOG/args"
FAKE_MODE=ok run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --id fixed-1
check "explicit id is used" test "$JOB" = "$DELEGATE_CACHE_DIR/fixed-1"
run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --id fixed-1
check "reused id exits 2" test "$CODE" -eq 2

# --- brief verbatim and cwd with spaces
printf '%s\n' 'Fix `foo` in "$HOME/x" & ünlü şçğ; rm -rf / # not a command' "line 2 'quoted'" > "$TMP/weird.md"
mkdir -p "$TMP/my proj"
FAKE_MODE=ok run --mode ro --cwd "$TMP/my proj" --brief "$TMP/weird.md"
check "brief verbatim: metacharacters and Turkish survive" cmp -s "$TMP/weird.md" "$FAKE_LOG/stdin"
check "cwd with spaces works" test "$(cat "$FAKE_LOG/pwd")" = "$(cd "$TMP/my proj" && pwd -P)"

# --- failures
FAKE_MODE=is_error run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "is_error result exits 1" test "$CODE" -eq 1
check "is_error recorded" test "$(meta .is_error)" = true
check "subtype recorded" test "$(meta .subtype)" = error_max_turns
check "permission denials recorded" test "$(meta '.permission_denials[0].tool_input.command')" = 'git push'

FAKE_MODE=crash run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "crash exits 1" test "$CODE" -eq 1
check "crash exit code recorded" test "$(meta .exit_code)" = 3
check "crash is_error true" test "$(meta .is_error)" = true
check "crash leaves empty result.md" test ! -s "$JOB/result.md"
check "crash stderr captured" grep -q boom "$JOB/stderr.log"

FAKE_MODE=big run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "~2 MB result: meta.json exists and parses" bash -c 'jq -e .exit_code "$1" >/dev/null 2>&1' _ "$JOB/meta.json"
check "~2 MB result: exits 0" test "$CODE" -eq 0
check "~2 MB result: result.md holds the report" test "$(wc -c < "$JOB/result.md")" -ge 2000000

# --- TERM mid-run
FAKE_MODE=sleep bash "$DELEGATE" --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --id term-1 >/dev/null 2>&1 &
PID=$!
sleep 2
kill -TERM "$PID"; wait "$PID"; CODE=$?
JOB="$DELEGATE_CACHE_DIR/term-1"
check "TERM mid-run exits 1" test "$CODE" -eq 1
check "TERM mid-run still writes meta" test -s "$JOB/meta.json"
check "TERM mid-run marks error" test "$(meta .is_error)" = true
check "TERM mid-run leaves no fake claude running" bash -c '! kill -0 "$(cat "$1/pid")" 2>/dev/null' _ "$FAKE_LOG"

# --- TERM right after start, before the child is up
FAKE_MODE=ok bash "$DELEGATE" --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --id term-2 >/dev/null 2>&1 &
PID=$!
sleep 0.05; kill -TERM "$PID" 2>/dev/null; wait "$PID"; CODE=$?
JOB="$DELEGATE_CACHE_DIR/term-2"
check "early TERM writes meta" test -s "$JOB/meta.json"

# --- SIGKILL: no meta.json, the watcher must notice via <job>/pid
FAKE_MODE=sleep bash "$DELEGATE" --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --id kill-1 >/dev/null 2>&1 &
PID=$!
sleep 2
JOB="$DELEGATE_CACHE_DIR/kill-1"
check "pid file holds delegate.sh's pid" test "$(cat "$JOB/pid" 2>/dev/null)" = "$PID"
kill -KILL "$PID"; wait "$PID" 2>/dev/null
kill -TERM "$(cat "$FAKE_LOG/pid")" 2>/dev/null   # the orphaned fake claude
WOUT="$(perl -e 'alarm 10; exec @ARGV' bash "$HERE/../scripts/watch.sh" "$JOB")"; wcode=$?
check "watch stops after SIGKILL (exit 1, not timeout)" test "$wcode" -eq 1
check "watch says the job process is gone" grep -qF 'job process is gone without meta.json' <<<"$WOUT"

rm -rf "$TMP"
exit $fail
