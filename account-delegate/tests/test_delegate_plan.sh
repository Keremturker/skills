#!/usr/bin/env bash
# Behavior test for delegate.sh plan mode (fake claude). Run: bash account-delegate/tests/test_delegate_plan.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
DELEGATE="$HERE/../scripts/delegate.sh"
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok: $d"; else echo "FAIL: $d"; fail=1; fi; }
meta() { jq -r "$1" "$JOB/meta.json"; }
run() { OUT="$(bash "$DELEGATE" "$@" 2>"$TMP/err")"; CODE=$?; JOB="$(sed -n 's/^JOB_DIR=//p' <<<"$OUT" | head -n 1)"; }
njobs() { ls "$1/jobs" 2>/dev/null | wc -l | tr -d ' '; }

TMP="$(mktemp -d)"
export DELEGATE_CLAUDE_BIN="$HERE/fake-claude.sh" DELEGATE_CLAUDE_CONFIG_DIR="$TMP/second" \
       DELEGATE_CACHE_DIR="$TMP/cache" FAKE_LOG="$TMP/log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$DELEGATE_CLAUDE_CONFIG_DIR" "$FAKE_LOG" "$TMP/plans"
printf 'Task brief\n' > "$TMP/brief.md"

REPO="$TMP/repo"; mkdir -p "$REPO/sub"
git -C "$REPO" init -q && echo base > "$REPO/README" && echo x > "$REPO/sub/keep" \
  && git -C "$REPO" add . && git -C "$REPO" commit -qm base
MAIN="$(git -C "$REPO" symbolic-ref --short HEAD)"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
PLAN="$TMP/plans/p1"
B="$TMP/brief.md"

# --- refusals before any plan exists
run --mode ro --plan "$PLAN" --cwd "$REPO" --brief "$B" --base "$MAIN"
check "--plan with ro exits 2" test "$CODE" -eq 2
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --base "$MAIN" --id x1
check "--plan with --id exits 2" test "$CODE" -eq 2
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "new plan without --base exits 2" test "$CODE" -eq 2
run --mode write --cwd "$REPO" --brief "$B" --base "$MAIN" --title t
check "--title without --plan exits 2" test "$CODE" -eq 2
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --base "$MAIN" --title "$(printf 'a\nb')"
check "multi-line --title exits 2" test "$CODE" -eq 2
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --base "$MAIN" --title "$(head -c 201 /dev/zero | tr '\0' a)"
check "--title over 200 chars exits 2" test "$CODE" -eq 2
run --mode write --plan "$TMP/plans/.hidden" --cwd "$REPO" --brief "$B" --base "$MAIN"
check "plan dir name starting with a dot exits 2" test "$CODE" -eq 2
run --mode write --plan "$TMP/plans/bad name" --cwd "$REPO" --brief "$B" --base "$MAIN"
check "plan dir name with a space exits 2" test "$CODE" -eq 2
check "refused calls wrote no plan.json" test ! -e "$PLAN/plan.json"
check "refused calls printed no JOB_DIR" test -z "$JOB"
mkdir -p "$TMP/plans/p2/junk"
run --mode write --plan "$TMP/plans/p2" --cwd "$REPO" --brief "$B" --base "$MAIN"
check "non-empty dir without plan.json exits 2" test "$CODE" -eq 2

# --- first job creates the plan
FAKE_MODE=write FAKE_FILE=a.txt run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --base "$MAIN" --title "Task 1: a"
PLANP="$(cd "$PLAN" && pwd -P)"
check "first plan job exits 0" test "$CODE" -eq 0
check "job dir is jobs/1" test "$JOB" = "$PLANP/jobs/1"
check "plan.json pins base, branch, cwd" jq -e --arg c "$BASE_SHA" --arg b "$MAIN" --arg cwd "$(cd "$REPO" && pwd -P)" \
  '.id == "p1" and .branch == "delegate/p1" and .base == $b and .base_commit == $c and .cwd == $cwd and (.gitdir | length > 0) and (.gitfile_hex | length > 0)' "$PLAN/plan.json"
check "plan.json is private" bash -c 'ls -l "$1/plan.json" | grep -q "^-rw-------"' _ "$PLAN"
check "worktree lives in the plan dir" test -f "$PLAN/worktree/a.txt"
check "agent runs in the plan worktree" test "$(cat "$FAKE_LOG/pwd")" = "$PLANP/worktree"
check "commit message uses the title" bash -c 'git -C "$1" log -1 --format=%s delegate/p1 | grep -qxF "delegate(p1): Task 1: a"' _ "$REPO"
check "meta.commit is the branch tip" test "$(meta .commit)" = "$(git -C "$REPO" rev-parse delegate/p1)"
check "meta plan fields" jq -e --arg c "$BASE_SHA" --arg pd "$PLANP" \
  '.plan_id == "p1" and .plan_dir == $pd and .job_n == 1 and .title == "Task 1: a" and .resumed_from == null and .parent_commit == $c and .id == "p1-1"' "$JOB/meta.json"
check "meta.base is the plan base" test "$(meta .base)" = "$MAIN"
check "user's tree untouched" test ! -e "$REPO/a.txt"
FIRST="$(meta .commit)"

# --- second job reuses the plan
FAKE_MODE=write FAKE_FILE=b.txt run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --title "Task 2: b"
check "second plan job exits 0" test "$CODE" -eq 0
check "job dir is jobs/2" test "$JOB" = "$PLANP/jobs/2"
check "second commit's parent is the first" test "$(git -C "$REPO" rev-parse delegate/p1^)" = "$FIRST"
check "meta.parent_commit is the first commit" test "$(meta .parent_commit)" = "$FIRST"
check "meta.base_commit still the plan base" test "$(meta .base_commit)" = "$BASE_SHA"
check "two commits over base" test "$(git -C "$REPO" rev-list --count "$MAIN..delegate/p1")" = 2
check "second commit holds only b.txt" bash -c 'test "$(git -C "$1" show --name-only --format= delegate/p1 | sed "/^\$/d")" = b.txt' _ "$REPO"

# --- a job with no changes adds no commit and keeps the worktree
TIP="$(git -C "$REPO" rev-parse delegate/p1)"
FAKE_MODE=ok run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --title "Task 3"
check "no-change job exits 0" test "$CODE" -eq 0
check "no-change job: meta.commit null" test "$(meta .commit)" = null
check "no-change job: branch tip unchanged" test "$(git -C "$REPO" rev-parse delegate/p1)" = "$TIP"
check "worktree kept" test -d "$PLAN/worktree"

FAKE_MODE=write FAKE_FILE=c.txt run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "untitled job: default commit message" bash -c 'git -C "$1" log -1 --format=%s delegate/p1 | grep -qxF "delegate(p1): job 4"' _ "$REPO"
check "untitled job: meta.title null" test "$(meta .title)" = null

# --- refusals on an existing plan (no new job dir)
N_BEFORE="$(njobs "$PLAN")"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --base "$MAIN"
check "--base on an existing plan exits 2" test "$CODE" -eq 2
run --mode write --plan "$PLAN" --cwd "$REPO/sub" --brief "$B"
check "different --cwd exits 2" test "$CODE" -eq 2
echo junk > "$PLAN/worktree/junk.txt"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "dirty worktree exits 2" bash -c 'test "$1" -eq 2 && grep -qi uncommitted "$2"' _ "$CODE" "$TMP/err"
rm -f "$PLAN/worktree/junk.txt"
git -C "$PLAN/worktree" checkout -q --detach
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "detached HEAD in the plan worktree exits 2" test "$CODE" -eq 2
git -C "$PLAN/worktree" checkout -q delegate/p1
cp "$PLAN/worktree/.git" "$TMP/gitfile.bak"
printf 'gitdir: %s\n' "$TMP/nowhere" > "$PLAN/worktree/.git"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "tampered .git exits 2 and names .git" bash -c 'test "$1" -eq 2 && grep -q "\.git" "$2"' _ "$CODE" "$TMP/err"
cp "$TMP/gitfile.bak" "$PLAN/worktree/.git"
check "refusals created no job dir" test "$(njobs "$PLAN")" = "$N_BEFORE"
FAKE_MODE=write FAKE_FILE=d.txt run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "plan still usable after refusals" test "$CODE" -eq 0

# --- plan dir with spaces in its parent path
SPLAN="$TMP/my plans/p5"
FAKE_MODE=write FAKE_FILE=e.txt run --mode write --plan "$SPLAN" --cwd "$REPO" --brief "$B" --base "$MAIN"
check "plan dir with spaces: create" test "$CODE" -eq 0
FAKE_MODE=write FAKE_FILE=f.txt run --mode write --plan "$SPLAN" --cwd "$REPO" --brief "$B"
check "plan dir with spaces: reuse" bash -c 'test "$1" -eq 0 && test "$(git -C "$2" rev-list --count "$3..delegate/p5")" = 2' _ "$CODE" "$REPO" "$MAIN"

rm -rf "$TMP"
exit $fail
