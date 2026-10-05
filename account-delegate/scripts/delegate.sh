#!/usr/bin/env bash
# Runs one job headless on a second Claude Code account and records it in a job dir.
# Usage: delegate.sh --mode ro|write --cwd <dir> --brief <file> [--id <id>]
# Exit: 0 success, 1 job failed, 2 usage error. First stdout line: JOB_DIR=<path>.
set -uo pipefail

usage() { echo "usage: delegate.sh --mode ro|write --cwd <dir> --brief <file> [--id <id>]" >&2; exit 2; }
die() { echo "delegate: $*" >&2; exit 2; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

MODE="" CWD="" BRIEF="" ID=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --mode) MODE="$2" ;;
    --cwd) CWD="$2" ;;
    --brief) BRIEF="$2" ;;
    --id) ID="$2" ;;
    *) usage ;;
  esac
  shift 2
done
case "$MODE" in ro|write) ;; *) usage ;; esac
[ -d "$CWD" ] || die "--cwd is not a directory: $CWD"
[ -s "$BRIEF" ] || die "--brief is missing or empty: $BRIEF"
CWD="$(cd "$CWD" && pwd -P)"

CONFIG="${DELEGATE_CLAUDE_CONFIG_DIR:-$HOME/.claude-work}"
[ -d "$CONFIG" ] || die "second account config dir not found: $CONFIG (set DELEGATE_CLAUDE_CONFIG_DIR)"
BIN="${DELEGATE_CLAUDE_BIN:-}"
if [ -z "$BIN" ]; then
  if [ -x "$HOME/.local/bin/claude" ]; then BIN="$HOME/.local/bin/claude"; else BIN="$(command -v claude || true)"; fi
fi
[ -n "$BIN" ] && [ -x "$BIN" ] || die "claude binary not found (set DELEGATE_CLAUDE_BIN)"
CACHE="${DELEGATE_CACHE_DIR:-$HOME/.cache/claude-delegate}"
MAX_TURNS="${DELEGATE_MAX_TURNS:-40}"
case "$MAX_TURNS" in ''|*[!0-9]*|0) die "DELEGATE_MAX_TURNS must be a positive integer" ;; esac

TOP="" PREFIX=""
if [ "$MODE" = write ]; then
  TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || die "write mode needs a git repository: $CWD"
  git -C "$TOP" rev-parse -q --verify HEAD >/dev/null || die "write mode needs at least one commit: $TOP"
  PREFIX="$(git -C "$CWD" rev-parse --show-prefix)"
fi

[ -n "$ID" ] || ID="$(date +%Y%m%d-%H%M%S)-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 4)"
case "$ID" in ''|*[!A-Za-z0-9._-]*|.*) die "invalid --id: $ID" ;; esac
JOB="$CACHE/$ID"
[ -e "$JOB" ] && die "job dir already exists: $JOB"
mkdir -p "$JOB" || die "cannot create $JOB"
JOB="$(cd "$JOB" && pwd)"
cp "$BRIEF" "$JOB/brief.md"
: > "$JOB/stderr.log"
CHILD="" INTERRUPTED=0
on_signal() { INTERRUPTED=1; [ -n "$CHILD" ] && kill -TERM "$CHILD" 2>/dev/null; return 0; }
trap on_signal TERM INT HUP
echo "JOB_DIR=$JOB"
STARTED="$(now)"

WORKDIR="$CWD" WORKTREE="" BRANCH="" COMMIT="" COMMIT_FAILED=false RESULT_LINE=""

write_meta() { # $1 = exit code of the claude run
  local r="${RESULT_LINE:-null}"
  jq -n --arg id "$ID" --arg mode "$MODE" --arg cwd "$CWD" --arg workdir "$WORKDIR" \
    --arg worktree "$WORKTREE" --arg branch "$BRANCH" --arg commit "$COMMIT" \
    --argjson commit_failed "$COMMIT_FAILED" --argjson exit_code "$1" --argjson r "$r" \
    --arg started "$STARTED" --arg finished "$(now)" '
    def opt: if . == "" then null else . end;
    {id: $id, mode: $mode, cwd: $cwd, workdir: $workdir,
     worktree: ($worktree | opt), branch: ($branch | opt), commit: ($commit | opt),
     commit_failed: $commit_failed, exit_code: $exit_code,
     is_error: (($r == null) or ($r.is_error == true) or ($exit_code != 0)),
     subtype: $r.subtype, num_turns: $r.num_turns, total_cost_usd: $r.total_cost_usd,
     permission_denials: ($r.permission_denials // []), session_id: $r.session_id,
     started_at: $started, finished_at: $finished}' > "$JOB/meta.json.tmp" \
    && mv "$JOB/meta.json.tmp" "$JOB/meta.json"
}

REPORT='You are running headless on behalf of another Claude Code session. No human can answer questions or approve permission prompts during this run. Do the task in the brief as far as your permissions allow. If a tool call is denied, do not try to reach the same outcome another way; record it instead. Finish with a report written in the language of the brief, with exactly these sections: "## Done", "## Findings", "## Blocked or needed commands" (each denied or needed command verbatim, with the reason it is needed), "## Open questions".'

case "$MODE" in
  ro)
    FLAGS=(--permission-mode default
           --allowedTools 'Read,Grep,Glob,WebSearch,WebFetch'
           --disallowedTools 'Edit,Write,NotebookEdit,Bash')
    REPORT="$REPORT This is a read-only job: do not try to change any file."
    ;;
  write)
    BRANCH="delegate/$ID"
    WORKTREE="$JOB/worktree"
    if ! git -C "$TOP" worktree add -q -b "$BRANCH" "$WORKTREE" HEAD >> "$JOB/stderr.log" 2>&1; then
      echo "Could not create the git worktree; see stderr.log." > "$JOB/result.md"
      BRANCH="" WORKTREE=""
      write_meta 1; exit 1
    fi
    WORKDIR="$WORKTREE/$PREFIX"
    FLAGS=(--permission-mode acceptEdits)
    REPORT="$REPORT Work only inside the current directory tree. Do not commit, push or create branches: your file changes are collected and committed for you after you finish."
    ;;
esac

cd "$WORKDIR" || { write_meta 1; exit 1; }
# Strip the parent session's identity: CLAUDECODE, every CLAUDE_CODE_* var, and the personal API key.
UNSET=(-u CLAUDECODE -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL -u ANTHROPIC_MODEL)
while IFS= read -r v; do UNSET+=(-u "$v"); done < <(compgen -e | grep '^CLAUDE_CODE_')
env "${UNSET[@]}" \
    CLAUDE_CONFIG_DIR="$CONFIG" \
    "$BIN" -p --output-format stream-json --verbose --max-turns "$MAX_TURNS" \
    --append-system-prompt "$REPORT" "${FLAGS[@]}" \
    < "$JOB/brief.md" > "$JOB/events.jsonl" 2>> "$JOB/stderr.log" &
CHILD=$!
[ "$INTERRUPTED" -eq 1 ] && kill -TERM "$CHILD" 2>/dev/null   # signal arrived before the child existed
wait "$CHILD"; CODE=$?
if kill -0 "$CHILD" 2>/dev/null; then   # wait was interrupted by a signal
  kill -TERM "$CHILD" 2>/dev/null; wait "$CHILD"; CODE=143
fi
trap '' TERM INT HUP   # stay alive until meta.json is written

RESULT_LINE="$(jq -R -c 'fromjson? | select(.type == "result")' "$JOB/events.jsonl" | tail -n 1)"
if [ -n "$RESULT_LINE" ]; then
  jq -r '.result // ""' <<<"$RESULT_LINE" > "$JOB/result.md"
else
  : > "$JOB/result.md"
fi

if [ "$MODE" = write ]; then
  if git -C "$WORKTREE" add -A >> "$JOB/stderr.log" 2>&1 && ! git -C "$WORKTREE" diff --cached --quiet; then
    if git -C "$WORKTREE" commit -q -m "delegate: $ID" >> "$JOB/stderr.log" 2>&1; then
      COMMIT="$(git -C "$WORKTREE" rev-parse HEAD)"
    else
      COMMIT_FAILED=true
    fi
  fi
fi

write_meta "$CODE"
[ "$(jq -r .is_error "$JOB/meta.json")" = false ] && exit 0 || exit 1
