#!/usr/bin/env bash
# Runs one job headless on a second Claude Code account and records it in a job dir.
# Usage: delegate.sh --mode ro|write --cwd <dir> --brief <file> [--base <ref>] [--id <id>]
#        delegate.sh --mode write --plan <plan dir> --cwd <dir> --brief <file> [--base <ref>] [--title <t>] [--resume <session id>]
#   --base <ref> (branch, tag or commit) is required when --cwd is inside a git repo and refused
#   otherwise. Every job in a git repo runs in its own worktree created from that ref; a job in
#   a non-git directory is read-only and runs directly in --cwd.
#   --plan: all jobs of one implementation plan share <plan dir>/worktree on branch
#   delegate/<plan id> (<plan id> = basename of <plan dir>). The first job creates the plan and
#   needs --base; later jobs reuse it and refuse --base. Each job gets <plan dir>/jobs/<n>/ and
#   adds at most one commit. --resume continues a session of an earlier job of the same plan.
# Exit: 0 success, 1 job failed, 2 usage error. First stdout line: JOB_DIR=<path>.
set -uo pipefail

usage() { echo "usage: delegate.sh --mode ro|write --cwd <dir> --brief <file> [--base <ref>] [--id <id>] | --mode write --plan <dir> --cwd <dir> --brief <file> [--base <ref>] [--title <t>] [--resume <session id>]" >&2; exit 2; }
die() { echo "delegate: $*" >&2; exit 2; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
wt_tampered() {   # true when the worktree or its .git file is not what `worktree add` made
  [ ! -d "$WORKTREE" ] || [ -L "$WORKTREE" ] || [ -L "$WORKTREE/.git" ] || [ ! -f "$WORKTREE/.git" ] \
    || [ "$(od -An -tx1 < "$WORKTREE/.git" | tr -d ' \n')" != "$GITFILE_HEX" ]
}
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
# repos. Nested repos are never entered: a gitlink already in the index (a submodule of the
# base, or a nested repo an earlier plan job committed) whose path still holds a nested repo is
# left out of `add` and status uses --ignore-submodules=all, since both would run `git status`
# inside it and so its own config (filters) as the user; a new nested repo is added as a gitlink
# without being entered. Changes inside an existing nested repo are therefore not collected. A
# gitlink whose nested repo is gone (deleted, or replaced by a file) has nothing to enter: it is
# collected like any other path. The user's own hooks still run at merge time.
cgit() {
  git --git-dir="$GITDIR" --work-tree="$WORKTREE" -c core.hooksPath=/dev/null \
      -c core.fsmonitor=false -c core.untrackedCache=false -c commit.gpgsign=false \
      -c maintenance.auto=false "$@"
}
gitlinks() {   # reads `ls-files -s -z` on stdin, prints the paths of its gitlinks, NUL-separated
  local e
  while IFS= read -r -d '' e; do [ "${e%% *}" != 160000 ] || printf '%s\0' "${e#*$'\t'}"; done
}
has_nested_repo() { [ -e "$1/.git" ] || [ -L "$1/.git" ]; }
collect_add() {   # add -A in the worktree, leaving out the gitlinks that still hold a nested repo
  cd "$WORKTREE" && cgit ls-files -s -z > "$JOB/index-entries" || return 1
  local p ps=(.)
  while IFS= read -r -d '' p; do ! has_nested_repo "$p" || ps+=(":(exclude,literal)$p"); done < <(gitlinks < "$JOB/index-entries")
  rm -f "$JOB/index-entries"
  cgit add -A -- "${ps[@]}"
}
pj() { jq -r "$1 // empty" "$PLAN/plan.json"; }   # one field of plan.json ("" when missing/null)
LOCKED=0
take_lock() {   # one job at a time per plan; a lock whose pid is no longer running is taken over
  if ! mkdir "$PLAN/lock" 2>/dev/null; then
    local p; p="$(cat "$PLAN/lock/pid" 2>/dev/null)"
    case "$p" in ''|*[!0-9]*) die "plan $PLAN_ID is locked ($PLAN/lock has no valid pid); another job may be running" ;; esac
    ! kill -0 "$p" 2>/dev/null || die "another job (pid $p) is running in plan $PLAN_ID"
    echo "delegate: took over a stale plan lock (pid $p)" >&2
  fi
  echo $$ > "$PLAN/lock/pid"; LOCKED=1
}
release_lock() {
  [ "$LOCKED" -eq 1 ] && [ "$(cat "$PLAN/lock/pid" 2>/dev/null)" = "$$" ] && rm -f "$PLAN/lock/pid" && rmdir "$PLAN/lock" 2>/dev/null
  return 0
}
trap release_lock EXIT

MODE="" CWD="" BRIEF="" ID="" BASE="" BASE_GIVEN=0 PLAN="" PLAN_ID="" TITLE="" RESUME=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --mode) MODE="$2" ;;
    --cwd) CWD="$2" ;;
    --brief) BRIEF="$2" ;;
    --id) ID="$2" ;;
    --base) BASE="$2"; BASE_GIVEN=1 ;;
    --plan) PLAN="$2" ;;
    --title) TITLE="$2" ;;
    --resume) RESUME="$2" ;;
    *) usage ;;
  esac
  shift 2
done
case "$MODE" in ro|write) ;; *) usage ;; esac
[ -d "$CWD" ] || die "--cwd is not a directory: $CWD"
[ -s "$BRIEF" ] || die "--brief is missing or empty: $BRIEF"
CWD="$(cd "$CWD" && pwd -P)"
if [ -n "$PLAN" ]; then
  [ "$MODE" = write ] || die "--plan is only for write mode"
  [ -z "$ID" ] || die "--plan and --id cannot be used together"
  PLAN_ID="$(basename "$PLAN")"
  case "$PLAN_ID" in ''|*[!A-Za-z0-9._-]*|.*) die "invalid plan dir name (use [A-Za-z0-9._-], no leading dot): $PLAN_ID" ;; esac
else
  [ -z "$TITLE" ] || die "--title needs --plan"
  [ -z "$RESUME" ] || die "--resume needs --plan"
fi
case "$TITLE" in *$'\n'*|*$'\r'*) die "--title must be a single line" ;; esac
[ "${#TITLE}" -le 200 ] || die "--title is longer than 200 characters"
case "$RESUME" in -*|*[!A-Za-z0-9_-]*) die "invalid --resume: $RESUME" ;; esac

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
# write mode only: auto lets the second account's own classifier approve safe shell commands;
# acceptEdits allows edits and denies every shell command. Nothing that skips permission checks.
PERM_MODE="${DELEGATE_PERMISSION_MODE:-auto}"
case "$PERM_MODE" in auto|acceptEdits) ;; *) die "DELEGATE_PERMISSION_MODE must be auto or acceptEdits: $PERM_MODE" ;; esac

PLAN_EXISTS=0 N="" PARENT_COMMIT="" WORKTREE="" BRANCH="" GITDIR="" GITFILE_HEX=""
if [ -n "$PLAN" ] && [ -f "$PLAN/plan.json" ]; then
  PLAN_EXISTS=1
  [ "$BASE_GIVEN" -eq 0 ] || die "--base was fixed when plan $PLAN_ID was created; drop --base"
  [ "$(pj .cwd)" = "$CWD" ] || die "--cwd must be $(pj .cwd) for plan $PLAN_ID"
fi
TOP="" PREFIX="" START_BRANCH="" BASE_COMMIT="" IN_GIT=0
if TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$TOP" ]; then IN_GIT=1; else TOP=""; fi
if [ "$IN_GIT" -eq 1 ]; then
  if [ "$PLAN_EXISTS" -eq 1 ]; then
    BASE="$(pj .base)" BASE_COMMIT="$(pj .base_commit)" BASE_GIVEN=1
    [ -n "$BASE_COMMIT" ] || die "plan.json has no base_commit: $PLAN"
  else
    [ "$BASE_GIVEN" -eq 1 ] && [ -n "$BASE" ] || die "--base <branch|tag|commit> is required inside a git repository: $CWD"
    case "$BASE" in -*) die "invalid --base: $BASE" ;; esac
    if git -C "$TOP" show-ref -q --verify "refs/heads/$BASE" 2>/dev/null \
       && git -C "$TOP" show-ref -q --verify "refs/tags/$BASE" 2>/dev/null; then
      die "--base is ambiguous (both a branch and a tag named $BASE); rename one or pass a commit sha"
    fi
    BASE_COMMIT="$(git -C "$TOP" rev-parse --verify -q "$BASE^{commit}" 2>/dev/null)" && [ -n "$BASE_COMMIT" ] \
      || die "--base does not resolve to a commit: $BASE"
  fi
  PREFIX="$(git -C "$CWD" rev-parse --show-prefix)"
  [ -z "$PREFIX" ] || [ "$(git -C "$TOP" cat-file -t "$BASE_COMMIT:${PREFIX%/}" 2>/dev/null)" = tree ] \
    || die "--cwd is not a directory on the base ($BASE): $CWD"
  START_BRANCH="$(git -C "$TOP" symbolic-ref -q --short HEAD)"   # empty when detached
else
  [ "$BASE_GIVEN" -eq 0 ] || die "--base is only for git repositories; $CWD is not in one"
  [ "$MODE" = ro ] || die "write mode needs a git repository: $CWD"
fi

umask 077   # plan and job dirs hold briefs, reports and the worktree: private to the user
if [ -n "$PLAN" ]; then
  mkdir -p "$PLAN" || die "cannot create $PLAN"
  PLAN="$(cd "$PLAN" && pwd -P)"
  take_lock
  if [ "$PLAN_EXISTS" -eq 1 ]; then
    BRANCH="$(pj .branch)" WORKTREE="$PLAN/worktree" GITDIR="$(pj .gitdir)" GITFILE_HEX="$(pj .gitfile_hex)"
    [ -n "$BRANCH" ] && [ -n "$GITDIR" ] && [ -n "$GITFILE_HEX" ] || die "plan.json is incomplete: $PLAN"
    ! wt_tampered || die "$WORKTREE/.git was changed or removed; run no git command inside it (see the skill's cleanup rules)"
    [ "$(cgit symbolic-ref -q HEAD)" = "refs/heads/$BRANCH" ] || die "the plan worktree is not on $BRANCH (detached or switched): $WORKTREE"
    PARENT_COMMIT="$(cgit rev-parse -q --verify 'HEAD^{commit}')" || die "cannot read the plan branch tip: $BRANCH"
    # status would recurse into nested repos (gitlinks) and run their own config (filters) as the user
    st="$(cd "$WORKTREE" && cgit status --porcelain --ignore-submodules=all)" || die "cannot check the plan worktree for changes: $WORKTREE"
    # --ignore-submodules=all also hides a gitlink whose nested repo is gone (deleted, or a file now)
    (cd "$WORKTREE" && cgit ls-files -s -z) > "$PLAN/index-entries" || die "cannot read the plan worktree's index: $WORKTREE"
    while IFS= read -r -d '' p; do has_nested_repo "$WORKTREE/$p" || st="$st gone:$p"; done < <(gitlinks < "$PLAN/index-entries")
    rm -f "$PLAN/index-entries"
    [ -z "$st" ] || die "the plan worktree has uncommitted changes (a failed collection?); inspect them safely (see the skill) and resolve them first: $WORKTREE"
    if [ -n "$RESUME" ]; then
      cat "$PLAN"/jobs/*/meta.json 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null | grep -qxF -- "$RESUME" \
        || die "--resume: session $RESUME does not belong to plan $PLAN_ID"
    fi
  else
    [ -z "$RESUME" ] || die "--resume: plan $PLAN_ID has no jobs yet"
    [ ! -e "$PLAN/worktree" ] && [ ! -e "$PLAN/plan.json.tmp" ] && [ ! -L "$PLAN/worktree" ] \
      || die "a previous attempt left a worktree but no plan.json; inspect and remove it, or use a new plan dir: $PLAN"
  fi
  N=1; while [ -e "$PLAN/jobs/$N" ]; do N=$((N + 1)); done
  ID="$PLAN_ID-$N"
  JOB="$PLAN/jobs/$N"
  mkdir -p "$PLAN/jobs" && mkdir "$JOB" || die "cannot create $JOB"
else
  [ -n "$ID" ] || ID="$(date +%Y%m%d-%H%M%S)-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 4)"
  case "$ID" in ''|*[!A-Za-z0-9._-]*|.*) die "invalid --id: $ID" ;; esac
  JOB="$CACHE/$ID"
  [ -e "$JOB" ] && die "job dir already exists: $JOB"
  mkdir -p "$JOB" || die "cannot create $JOB"
fi
JOB="$(cd "$JOB" && pwd)"
echo $$ > "$JOB/pid"   # lets watch.sh notice a delegate.sh that died without writing meta.json
cp "$BRIEF" "$JOB/brief.md"
: > "$JOB/stderr.log"
CHILD="" INTERRUPTED=0
on_signal() { INTERRUPTED=1; [ -n "$CHILD" ] && kill -TERM "$CHILD" 2>/dev/null; return 0; }
trap on_signal TERM INT HUP
echo "JOB_DIR=$JOB"
STARTED="$(now)"

WORKDIR="$CWD" COMMIT="" COMMIT_FAILED=false RESULT_FILE=/dev/null RAN_MODE=""

write_meta() { # $1 = exit code of the claude run
  # The result line goes in by file: it can be megabytes, more than fits in an argument.
  if ! jq -n --arg id "$ID" --arg mode "$MODE" --arg cwd "$CWD" --arg workdir "$WORKDIR" \
    --arg worktree "$WORKTREE" --arg branch "$BRANCH" --arg commit "$COMMIT" \
    --arg start_branch "$START_BRANCH" --arg base "$BASE" --arg base_commit "$BASE_COMMIT" \
    --argjson base_given "$([ "$BASE_GIVEN" -eq 1 ] && echo true || echo false)" \
    --argjson commit_failed "$COMMIT_FAILED" --argjson exit_code "$1" --slurpfile rs "$RESULT_FILE" \
    --arg plan_id "$PLAN_ID" --arg plan_dir "$PLAN" --arg job_n "$N" --arg title "$TITLE" \
    --arg resumed_from "$RESUME" --arg parent_commit "$PARENT_COMMIT" --arg permission_mode "$RAN_MODE" --arg gitdir "$([ "$MODE" = write ] && echo "$GITDIR")" \
    --arg started "$STARTED" --arg finished "$(now)" '
    def opt: if . == "" then null else . end;
    ($rs[0] // null) as $r |
    {id: $id, mode: $mode, cwd: $cwd, workdir: $workdir,
     worktree: ($worktree | opt), branch: ($branch | opt), commit: ($commit | opt),
     start_branch: ($start_branch | opt),
     base: (if $base_given then $base else null end), base_commit: ($base_commit | opt),
     commit_failed: $commit_failed, exit_code: $exit_code,
     plan_id: ($plan_id | opt), plan_dir: ($plan_dir | opt),
     job_n: (if $job_n == "" then null else ($job_n | tonumber) end),
     title: ($title | opt), resumed_from: ($resumed_from | opt), parent_commit: ($parent_commit | opt), permission_mode: ($permission_mode | opt), gitdir: ($gitdir | opt),
     is_error: (($r == null) or ($r.is_error == true) or ($exit_code != 0)),
     subtype: $r.subtype, num_turns: $r.num_turns, total_cost_usd: $r.total_cost_usd,
     permission_denials: ($r.permission_denials // []), session_id: $r.session_id,
     started_at: $started, finished_at: $finished}' > "$JOB/meta.json.tmp" 2>> "$JOB/stderr.log"; then
    # Fallback so watch.sh and the caller always get a meta.json. ID is [A-Za-z0-9._-],
    # MODE is ro|write, BRANCH is delegate/<ID> or delegate/<plan id> and COMMIT is hex, so no escaping is needed.
    local b=null c=null bc=null bs=null w=null
    # base and worktree are free text: include them only when they need no JSON escaping
    case "$BASE" in ''|*[!A-Za-z0-9._/@+-]*) ;; *) [ "$BASE_GIVEN" -eq 1 ] && bs="\"$BASE\"" ;; esac
    case "$WORKTREE" in ''|*[!A-Za-z0-9._/@+-]*) ;; *) w="\"$WORKTREE\"" ;; esac
    [ -n "$BRANCH" ] && b="\"$BRANCH\""
    [ -n "$COMMIT" ] && c="\"$COMMIT\""
    [ -n "$BASE_COMMIT" ] && bc="\"$BASE_COMMIT\""
    echo "delegate: could not build meta.json with jq; wrote a minimal one" >> "$JOB/stderr.log"
    printf '{"id":"%s","mode":"%s","exit_code":%d,"is_error":true,"branch":%s,"commit":%s,"base":%s,"base_commit":%s,"worktree":%s,"commit_failed":%s}\n' \
      "$ID" "$MODE" "$1" "$b" "$c" "$bs" "$bc" "$w" "$COMMIT_FAILED" > "$JOB/meta.json.tmp"
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
      if ! git -C "$TOP" -c core.hooksPath=/dev/null worktree add -q --detach "$WORKTREE" "$BASE_COMMIT" >> "$JOB/stderr.log" 2>&1; then
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
    if [ "$PLAN_EXISTS" -eq 0 ]; then
      if [ -n "$PLAN" ]; then BRANCH="delegate/$PLAN_ID" WORKTREE="$PLAN/worktree"
      else BRANCH="delegate/$ID" WORKTREE="$JOB/worktree"; fi
      if ! git -C "$TOP" -c core.hooksPath=/dev/null worktree add -q -b "$BRANCH" "$WORKTREE" "$BASE_COMMIT" >> "$JOB/stderr.log" 2>&1; then
        echo "Could not create the git worktree; see stderr.log." > "$JOB/result.md"
        [ -z "$PLAN" ] || ! git -C "$TOP" show-ref -q --verify "refs/heads/$BRANCH" \
          || echo "Likely cause: branch $BRANCH already exists; delete or rename it, then retry." | tee -a "$JOB/stderr.log" >> "$JOB/result.md"
        BRANCH="" WORKTREE=""
        write_meta 1; exit 1
      fi
      # Pin the worktree's git dir and its .git file now, before the agent can touch them.
      GITDIR="$(git -C "$WORKTREE" rev-parse --absolute-git-dir)"
      GITFILE_HEX="$(od -An -tx1 < "$WORKTREE/.git" | tr -d ' \n')"
      if [ -n "$PLAN" ]; then
        PARENT_COMMIT="$BASE_COMMIT"
        if ! jq -n --arg id "$PLAN_ID" --arg repo "$TOP" --arg cwd "$CWD" --arg prefix "$PREFIX" \
            --arg branch "$BRANCH" --arg base "$BASE" --arg base_commit "$BASE_COMMIT" \
            --arg start_branch "$START_BRANCH" --arg gitdir "$GITDIR" --arg gitfile_hex "$GITFILE_HEX" \
            --arg created "$(now)" \
            '{id: $id, repo: $repo, cwd: $cwd, prefix: $prefix, branch: $branch, base: $base,
              base_commit: $base_commit, start_branch: (if $start_branch == "" then null else $start_branch end),
              gitdir: $gitdir, gitfile_hex: $gitfile_hex, created_at: $created}' > "$PLAN/plan.json.tmp" 2>> "$JOB/stderr.log" \
           || ! mv "$PLAN/plan.json.tmp" "$PLAN/plan.json"; then
          echo "Could not write plan.json; see stderr.log." > "$JOB/result.md"
          write_meta 1; exit 1
        fi
      fi
    fi
    WORKDIR="$WORKTREE/$PREFIX"
    FLAGS=(--permission-mode "$PERM_MODE")
    [ -z "$RESUME" ] || FLAGS+=(--resume "$RESUME")
    REPORT="$REPORT Work only inside the current directory tree. Do not commit, push or create branches: your file changes are collected and committed for you after you finish. Shell commands, if allowed, only inside the current directory tree: no package installs, no network calls, no git commands that change history or config."
    ;;
esac

ro_cleanup() {   # ro, git repo: remove the throwaway worktree (no --force)
  [ "$MODE" = ro ] && [ -n "$WORKTREE" ] || return 0
  # If the .git file changed, or the removal is refused, leave it and say so; meta.worktree then names it.
  if wt_tampered; then
    echo "delegate: $WORKTREE/.git was changed or removed during the run; the worktree was left in place. Do not run git inside it." >> "$JOB/stderr.log"
  elif git -C "$TOP" -c core.hooksPath=/dev/null -c core.fsmonitor=false worktree remove "$WORKTREE" >> "$JOB/stderr.log" 2>&1; then
    WORKTREE=""
  else
    echo "delegate: could not remove the read-only worktree; it was left at $WORKTREE" >> "$JOB/stderr.log"
  fi
}

cd "$WORKDIR" || { echo "delegate: cannot enter $WORKDIR" >> "$JOB/stderr.log"; ro_cleanup; write_meta 1; exit 1; }
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
RAN_MODE="$(jq -R -r 'fromjson? | select(.type == "system" and .subtype == "init") | .permissionMode // empty' "$JOB/events.jsonl" | head -n 1)"
jq -r '.result // ""' "$RESULT_FILE" > "$JOB/result.md"   # empty when there is no result line

# Throwaway ro worktree: removed while signals are still ignored, before meta is written.
ro_cleanup
if [ "$MODE" = write ]; then
  if wt_tampered; then
    COMMIT_FAILED=true
    echo "delegate: $WORKTREE/.git was changed or removed during the run; nothing was collected or committed. Do not run git inside the worktree (its .git may point at a git dir the agent built); inspect the files with plain tools." >> "$JOB/stderr.log"
  elif ! (collect_add) >> "$JOB/stderr.log" 2>&1; then
    COMMIT_FAILED=true
  elif ! cgit diff --cached --quiet; then
    if [ -n "$PLAN" ]; then MSG="delegate($PLAN_ID): ${TITLE:-job $N}"; else MSG="delegate: $ID"; fi
    if cgit commit -q --no-verify -m "$MSG" >> "$JOB/stderr.log" 2>&1; then
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
