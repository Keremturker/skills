#!/usr/bin/env bash
# Runs one job headless on a second Claude Code account and records it in a job dir.
# Usage: delegate.sh --mode ro|write --cwd <dir> --brief <file> [--base <ref>] [--id <id>]
#   --base <ref> (branch, tag or commit) is required when --cwd is inside a git repo and refused
#   otherwise. Every job in a git repo runs in its own worktree created from that ref; a job in
#   a non-git directory is read-only and runs directly in --cwd.
# Exit: 0 success, 1 job failed, 2 usage error. First stdout line: JOB_DIR=<path>.
set -uo pipefail

usage() { echo "usage: delegate.sh --mode ro|write --cwd <dir> --brief <file> [--base <ref>] [--id <id>]" >&2; exit 2; }
die() { echo "delegate: $*" >&2; exit 2; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

MODE="" CWD="" BRIEF="" ID="" BASE="" BASE_GIVEN=0
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --mode) MODE="$2" ;;
    --cwd) CWD="$2" ;;
    --brief) BRIEF="$2" ;;
    --id) ID="$2" ;;
    --base) BASE="$2"; BASE_GIVEN=1 ;;
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

TOP="" PREFIX="" START_BRANCH="" BASE_COMMIT="" IN_GIT=0
if TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$TOP" ]; then IN_GIT=1; else TOP=""; fi
if [ "$IN_GIT" -eq 1 ]; then
  [ "$BASE_GIVEN" -eq 1 ] && [ -n "$BASE" ] || die "--base <branch|tag|commit> is required inside a git repository: $CWD"
  case "$BASE" in -*) die "invalid --base: $BASE" ;; esac
  BASE_COMMIT="$(git -C "$TOP" rev-parse --verify -q "$BASE^{commit}" 2>/dev/null)" && [ -n "$BASE_COMMIT" ] \
    || die "--base does not resolve to a commit: $BASE"
  PREFIX="$(git -C "$CWD" rev-parse --show-prefix)"
  [ -z "$PREFIX" ] || git -C "$TOP" cat-file -e "$BASE_COMMIT:${PREFIX%/}" 2>/dev/null \
    || die "--cwd does not exist on the base ($BASE): $CWD"
  START_BRANCH="$(git -C "$TOP" symbolic-ref -q --short HEAD)"   # empty when detached
else
  [ "$BASE_GIVEN" -eq 0 ] || die "--base is only for git repositories; $CWD is not in one"
  [ "$MODE" = ro ] || die "write mode needs a git repository: $CWD"
fi

[ -n "$ID" ] || ID="$(date +%Y%m%d-%H%M%S)-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 4)"
case "$ID" in ''|*[!A-Za-z0-9._-]*|.*) die "invalid --id: $ID" ;; esac
JOB="$CACHE/$ID"
[ -e "$JOB" ] && die "job dir already exists: $JOB"
umask 077   # job dirs hold briefs, reports and the worktree: private to the user
mkdir -p "$JOB" || die "cannot create $JOB"
JOB="$(cd "$JOB" && pwd)"
echo $$ > "$JOB/pid"   # lets watch.sh notice a delegate.sh that died without writing meta.json
cp "$BRIEF" "$JOB/brief.md"
: > "$JOB/stderr.log"
CHILD="" INTERRUPTED=0
on_signal() { INTERRUPTED=1; [ -n "$CHILD" ] && kill -TERM "$CHILD" 2>/dev/null; return 0; }
trap on_signal TERM INT HUP
echo "JOB_DIR=$JOB"
STARTED="$(now)"

WORKDIR="$CWD" WORKTREE="" BRANCH="" COMMIT="" COMMIT_FAILED=false RESULT_FILE=/dev/null

write_meta() { # $1 = exit code of the claude run
  # The result line goes in by file: it can be megabytes, more than fits in an argument.
  if ! jq -n --arg id "$ID" --arg mode "$MODE" --arg cwd "$CWD" --arg workdir "$WORKDIR" \
    --arg worktree "$WORKTREE" --arg branch "$BRANCH" --arg commit "$COMMIT" \
    --arg start_branch "$START_BRANCH" --arg base "$BASE" --arg base_commit "$BASE_COMMIT" \
    --argjson base_given "$([ "$BASE_GIVEN" -eq 1 ] && echo true || echo false)" \
    --argjson commit_failed "$COMMIT_FAILED" --argjson exit_code "$1" --slurpfile rs "$RESULT_FILE" \
    --arg started "$STARTED" --arg finished "$(now)" '
    def opt: if . == "" then null else . end;
    ($rs[0] // null) as $r |
    {id: $id, mode: $mode, cwd: $cwd, workdir: $workdir,
     worktree: ($worktree | opt), branch: ($branch | opt), commit: ($commit | opt),
     start_branch: ($start_branch | opt),
     base: (if $base_given then $base else null end), base_commit: ($base_commit | opt),
     commit_failed: $commit_failed, exit_code: $exit_code,
     is_error: (($r == null) or ($r.is_error == true) or ($exit_code != 0)),
     subtype: $r.subtype, num_turns: $r.num_turns, total_cost_usd: $r.total_cost_usd,
     permission_denials: ($r.permission_denials // []), session_id: $r.session_id,
     started_at: $started, finished_at: $finished}' > "$JOB/meta.json.tmp" 2>> "$JOB/stderr.log"; then
    # Fallback so watch.sh and the caller always get a meta.json. ID is [A-Za-z0-9._-],
    # MODE is ro|write, BRANCH is delegate/<ID> and COMMIT is hex, so no escaping is needed.
    local b=null c=null bc=null
    [ -n "$BRANCH" ] && b="\"$BRANCH\""
    [ -n "$COMMIT" ] && c="\"$COMMIT\""
    [ -n "$BASE_COMMIT" ] && bc="\"$BASE_COMMIT\""
    echo "delegate: could not build meta.json with jq; wrote a minimal one" >> "$JOB/stderr.log"
    printf '{"id":"%s","mode":"%s","exit_code":%d,"is_error":true,"branch":%s,"commit":%s,"base_commit":%s,"commit_failed":%s}\n' \
      "$ID" "$MODE" "$1" "$b" "$c" "$bc" "$COMMIT_FAILED" > "$JOB/meta.json.tmp"
  fi
  mv "$JOB/meta.json.tmp" "$JOB/meta.json"
}

REPORT='You are running headless on behalf of another Claude Code session. No human can answer questions or approve permission prompts during this run. Do the task in the brief as far as your permissions allow. If a tool call is denied, do not try to reach the same outcome another way; record it instead. Finish with a report written in the language of the brief, with exactly these sections: "## Done", "## Findings", "## Blocked or needed commands" (each denied or needed command verbatim, with the reason it is needed), "## Open questions".'

case "$MODE" in
  ro)
    FLAGS=(--permission-mode default
           --allowedTools 'Read,Grep,Glob,WebSearch,WebFetch'
           --disallowedTools 'Edit,Write,NotebookEdit,Bash')
    REPORT="$REPORT This is a read-only job: do not try to change any file."
    if [ "$IN_GIT" -eq 1 ]; then
      WORKTREE="$JOB/worktree"
      if ! git -C "$TOP" worktree add -q --detach "$WORKTREE" "$BASE_COMMIT" >> "$JOB/stderr.log" 2>&1; then
        echo "Could not create the git worktree; see stderr.log." > "$JOB/result.md"
        WORKTREE=""
        write_meta 1; exit 1
      fi
      GITDIR="$(git -C "$WORKTREE" rev-parse --absolute-git-dir)"
      GITFILE_HEX="$(od -An -tx1 < "$WORKTREE/.git" | tr -d ' \n')"
      WORKDIR="$WORKTREE/$PREFIX"
    fi
    ;;
  write)
    BRANCH="delegate/$ID"
    WORKTREE="$JOB/worktree"
    if ! git -C "$TOP" worktree add -q -b "$BRANCH" "$WORKTREE" "$BASE_COMMIT" >> "$JOB/stderr.log" 2>&1; then
      echo "Could not create the git worktree; see stderr.log." > "$JOB/result.md"
      BRANCH="" WORKTREE=""
      write_meta 1; exit 1
    fi
    # Pin the worktree's git dir and its .git file now, before the agent can touch them.
    GITDIR="$(git -C "$WORKTREE" rev-parse --absolute-git-dir)"
    GITFILE_HEX="$(od -An -tx1 < "$WORKTREE/.git" | tr -d ' \n')"
    WORKDIR="$WORKTREE/$PREFIX"
    FLAGS=(--permission-mode acceptEdits)
    REPORT="$REPORT Work only inside the current directory tree. Do not commit, push or create branches: your file changes are collected and committed for you after you finish."
    ;;
esac

cd "$WORKDIR" || { write_meta 1; exit 1; }
# Strip the parent session's identity: CLAUDECODE, every CLAUDE_CODE_* and every ANTHROPIC_* var
# (API key, auth token, base URL, models, custom headers, ...).
UNSET=(-u CLAUDECODE)
while IFS= read -r v; do UNSET+=(-u "$v"); done < <(compgen -e | grep -E '^(CLAUDE_CODE_|ANTHROPIC_)')
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

jq -R -c 'fromjson? | select(.type == "result")' "$JOB/events.jsonl" | tail -n 1 > "$JOB/result-line.json"
RESULT_FILE="$JOB/result-line.json"
jq -r '.result // ""' "$RESULT_FILE" > "$JOB/result.md"   # empty when there is no result line

# Collection runs as the user, outside the second account's sandbox, over a tree the agent
# controlled. Nothing in that tree may decide what git executes:
# - the git dir is the one pinned right after `worktree add`, never the tree's .git file
#   (a rewritten .git could name a git dir with core.fsmonitor=<cmd>, which `add` runs);
#   if the .git file changed at all, nothing is collected and the worktree is left as is;
# - hooks are off (core.hooksPath=/dev/null plus --no-verify), so a tracked hooks dir
#   (core.hooksPath=.hooks, husky) edited by the agent never runs here;
# - core.fsmonitor is off; -c values also reach any git child process.
# Residual: clean/smudge filters named in the tree's .gitattributes run if the user's own git
# config defines them (e.g. git-lfs). Those are programs the user installed, fed the agent's
# file contents, as in any `git add` of untrusted files; overriding them would corrupt LFS
# repos. Nested repos the agent creates are added as gitlinks; add/commit do not run their
# config (commit does not recurse into them). The user's own hooks still run at merge time.
cgit() {
  git --git-dir="$GITDIR" --work-tree="$WORKTREE" -c core.hooksPath=/dev/null \
      -c core.fsmonitor=false -c core.untrackedCache=false -c commit.gpgsign=false \
      -c maintenance.auto=false "$@"
}
wt_tampered() {   # true when the worktree or its .git file is not what `worktree add` made
  [ ! -d "$WORKTREE" ] || [ -L "$WORKTREE" ] || [ -L "$WORKTREE/.git" ] || [ ! -f "$WORKTREE/.git" ] \
    || [ "$(od -An -tx1 < "$WORKTREE/.git" | tr -d ' \n')" != "$GITFILE_HEX" ]
}
if [ "$MODE" = ro ] && [ -n "$WORKTREE" ]; then
  # Throwaway worktree: remove it (no --force) while signals are still ignored. If the .git file
  # changed, or the removal is refused, leave it and say so; meta.worktree then names it.
  if wt_tampered; then
    echo "delegate: $WORKTREE/.git was changed or removed during the run; the worktree was left in place. Do not run git inside it." >> "$JOB/stderr.log"
  elif git -C "$TOP" -c core.hooksPath=/dev/null -c core.fsmonitor=false worktree remove "$WORKTREE" >> "$JOB/stderr.log" 2>&1; then
    WORKTREE=""
  else
    echo "delegate: could not remove the read-only worktree; it was left at $WORKTREE" >> "$JOB/stderr.log"
  fi
fi
if [ "$MODE" = write ]; then
  if wt_tampered; then
    COMMIT_FAILED=true
    echo "delegate: $WORKTREE/.git was changed or removed during the run; nothing was collected or committed. Do not run git inside the worktree (its .git may point at a git dir the agent built); inspect the files with plain tools." >> "$JOB/stderr.log"
  elif ! (cd "$WORKTREE" && cgit add -A) >> "$JOB/stderr.log" 2>&1; then
    COMMIT_FAILED=true
  elif ! cgit diff --cached --quiet; then
    if cgit commit -q --no-verify -m "delegate: $ID" >> "$JOB/stderr.log" 2>&1; then
      COMMIT="$(cgit rev-parse -q --verify 'HEAD^{commit}')"
      if [ -z "$COMMIT" ] || [ "$COMMIT" != "$(cgit rev-parse -q --verify "refs/heads/$BRANCH^{commit}")" ]; then
        echo "delegate: the new commit is not the tip of $BRANCH; not reporting it" >> "$JOB/stderr.log"
        COMMIT="" COMMIT_FAILED=true
      fi
    else
      COMMIT_FAILED=true
    fi
  fi
fi

write_meta "$CODE"
rm -f "$JOB/result-line.json"
[ "$(jq -r .is_error "$JOB/meta.json")" = false ] && exit 0 || exit 1
