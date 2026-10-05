# account-delegate Plan Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `delegate.sh` run every task of an implementation plan in one shared worktree/branch on the second account (with `--plan`, `--title`, `--resume`, a plan lock), and document the plan-mode loop in which the main session reviews each task.

**Architecture:** `delegate.sh` gains a plan mode (write only): the first call creates `<PLAN_DIR>/plan.json`, `<PLAN_DIR>/worktree` and branch `delegate/<plan-id>`, pinning the git dir and `.git` file; later calls reuse them after re-checking the pins, and every call gets its own `<PLAN_DIR>/jobs/<n>/` job dir and adds one commit. `--resume` continues a second-account session that belongs to the plan. `SKILL.md` gets a "Plan mode" section describing the controller loop (brief → job → review → fix rounds → next task).

**Tech Stack:** bash, git, jq; tests use `tests/fake-claude.sh` (never the real CLI).

**Spec:** `docs/superpowers/specs/2026-10-05-account-delegate-plan-mode-design.md`

All paths below are relative to the repo root `/Users/keremturker/StudioProjects/ProjectGenerator/skills`.
`~/.claude/skills/account-delegate` is a symlink to `account-delegate/`, so edits are live.

## Global Constraints

- Plan mode is write mode only: `--plan` with `--mode ro` exits 2.
- Exit codes keep their meaning: 0 success, 1 job failed, 2 usage error **with no job dir created**. Every plan-mode refusal (bad flags, tampered `.git`, dirty worktree, unknown `--resume`, held lock) happens before `JOB_DIR=` is printed and exits 2.
- Plan id = basename of `PLAN_DIR`, must match `[A-Za-z0-9._-]` and not start with `.`.
- `--title`: only with `--plan`, one line, at most 200 characters. Commit message `delegate(<plan-id>): <title>`, or `delegate(<plan-id>): job <n>` without a title.
- `--resume <session_id>`: only with `--plan`; value `[A-Za-z0-9_-]`, not starting with `-`; must equal the `session_id` of some `PLAN_DIR/jobs/*/meta.json`.
- `--base` is required when the plan is created and refused once `plan.json` exists. `--cwd` of later calls must equal `plan.json.cwd`. `--plan` and `--id` are mutually exclusive.
- The plan worktree is never removed by `delegate.sh`.
- Collection safety is unchanged: pinned git dir, `core.hooksPath=/dev/null`, `--no-verify`, `core.fsmonitor=false`; a changed `.git` file means nothing is collected.
- New `meta.json` fields: `plan_id`, `plan_dir`, `job_n` (number), `title`, `resumed_from`, `parent_commit` — all null outside plan mode.
- Non-plan calls behave exactly as today; `tests/test_delegate.sh`, `tests/test_delegate_write.sh`, `tests/test_watch.sh` must keep passing unchanged.
- Never add MCP servers, plugin dirs, agents, permission-bypass flags or approval hooks to the second account's run.

## Review Focus

1. A previous job's collection failed (`commit_failed`) and left edits in the plan worktree → the next plan call must refuse (exit 2), not silently fold those edits into the next task's commit. (Task 1 test "dirty worktree".)
2. The agent detached HEAD or switched branches in the plan worktree → the next call must refuse (exit 2), since its commit would not land on `delegate/<plan-id>`. (Task 1 test "detached HEAD".)
3. A plan dir path containing spaces (e.g. `~/My Plans/p1`) → plan creation and reuse work. (Task 1 test "plan dir with spaces".)
4. A job crashes (claude exits non-zero) in plan mode → `meta.json` is written, the lock is released, and the next task can run. (Task 3 test "crash releases lock".)
5. `--resume` with the session id of a job from a *different* plan → refused (exit 2). (Task 2 test "foreign session".)

---

### Task 1: `--plan` and `--title` in `delegate.sh`

**Files:**
- Modify: `account-delegate/scripts/delegate.sh`
- Modify: `account-delegate/tests/fake-claude.sh` (write mode: `FAKE_FILE`, `FAKE_SESSION`)
- Create: `account-delegate/tests/test_delegate_plan.sh`

**Interfaces:**
- Produces (CLI): `delegate.sh --mode write --plan <dir> --cwd <dir> --brief <file> [--base <ref>] [--title <t>]`
- Produces (files): `<PLAN_DIR>/plan.json` with keys `id, repo, cwd, prefix, branch, base, base_commit, start_branch, gitdir, gitfile_hex, created_at`; `<PLAN_DIR>/worktree/`; `<PLAN_DIR>/jobs/<n>/` (same contents as a normal job dir).
- Produces (meta.json): `plan_id, plan_dir, job_n, title, resumed_from, parent_commit`.
- Produces (shell, used by Tasks 2–3): variables `PLAN` (absolute, `pwd -P`), `PLAN_ID`, `PLAN_EXISTS` (0/1), `N`, `RESUME` (parsed but validated in Task 2), function `pj <jq filter>` reading `plan.json`, functions `wt_tampered` and `cgit` defined before any use.
- Produces (fake-claude): write mode writes `${FAKE_FILE:-fake.txt}` and reports `session_id` `${FAKE_SESSION:-s2}`.

- [ ] **Step 1: Extend fake-claude write mode**

In `account-delegate/tests/fake-claude.sh`, replace the `write)` case with:

```bash
  write)
    echo hello > "${FAKE_FILE:-fake.txt}"
    printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.1,"session_id":"%s","permission_denials":[],"result":"wrote %s"}\n' \
      "${FAKE_SESSION:-s2}" "${FAKE_FILE:-fake.txt}"
    ;;
```

- [ ] **Step 2: Write the failing test file**

Create `account-delegate/tests/test_delegate_plan.sh`:

```bash
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
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash account-delegate/tests/test_delegate_plan.sh; echo "exit $?"`
Expected: several `FAIL:` lines (e.g. `FAIL: first plan job exits 0`, since `--plan` is an unknown flag) and `exit 1`.

- [ ] **Step 4: Implement `--plan` / `--title` in `delegate.sh`**

Make these edits to `account-delegate/scripts/delegate.sh`.

4a. Header comment and `usage()` — replace the first comment block lines 2–6 and the `usage()` line with:

```bash
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
```

4b. Argument parsing — replace the `MODE=... BASE_GIVEN=0` line and add three cases:

```bash
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
```

4c. Right after `CWD="$(cd "$CWD" && pwd -P)"`, add the plan flag checks:

```bash
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
```

4d. Move the helpers `wt_tampered()` and `cgit()` (and the long comment block above `cgit()`) up so they are defined right after `now()`; delete them from their old positions. They only reference `WORKTREE`, `GITDIR`, `GITFILE_HEX`, which are set before they are called. Add a reader for `plan.json` next to them:

```bash
pj() { jq -r "$1 // empty" "$PLAN/plan.json"; }   # one field of plan.json ("" when missing/null)
```

4e. Load an existing plan before the git block. Insert immediately before the line `TOP="" PREFIX="" START_BRANCH="" BASE_COMMIT="" IN_GIT=0`:

```bash
PLAN_EXISTS=0 N="" PARENT_COMMIT="" WORKTREE="" BRANCH="" GITDIR="" GITFILE_HEX=""
if [ -n "$PLAN" ] && [ -f "$PLAN/plan.json" ]; then
  PLAN_EXISTS=1
  [ "$BASE_GIVEN" -eq 0 ] || die "--base was fixed when plan $PLAN_ID was created; drop --base"
  [ "$(pj .cwd)" = "$CWD" ] || die "--cwd must be $(pj .cwd) for plan $PLAN_ID"
fi
```

Then, inside the `if [ "$IN_GIT" -eq 1 ]; then` block, replace the base-resolution part — everything from `[ "$BASE_GIVEN" -eq 1 ] && [ -n "$BASE" ] || die ...` through the `BASE_COMMIT=... || die "--base does not resolve to a commit: $BASE"` line — with:

```bash
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
```

The `PREFIX=...`, cwd-on-base check and `START_BRANCH=...` lines that follow stay as they are.

4f. Replace the job-dir block — from `[ -n "$ID" ] || ID=...` through `JOB="$(cd "$JOB" && pwd)"` — with:

```bash
umask 077   # plan and job dirs hold briefs, reports and the worktree: private to the user
if [ -n "$PLAN" ]; then
  mkdir -p "$PLAN" || die "cannot create $PLAN"
  PLAN="$(cd "$PLAN" && pwd -P)"
  if [ "$PLAN_EXISTS" -eq 1 ]; then
    BRANCH="$(pj .branch)" WORKTREE="$PLAN/worktree" GITDIR="$(pj .gitdir)" GITFILE_HEX="$(pj .gitfile_hex)"
    [ -n "$BRANCH" ] && [ -n "$GITDIR" ] && [ -n "$GITFILE_HEX" ] || die "plan.json is incomplete: $PLAN"
    ! wt_tampered || die "$WORKTREE/.git was changed or removed; run no git command inside it (see the skill's cleanup rules)"
    [ "$(cgit symbolic-ref -q HEAD)" = "refs/heads/$BRANCH" ] || die "the plan worktree is not on $BRANCH (detached or switched): $WORKTREE"
    PARENT_COMMIT="$(cgit rev-parse -q --verify 'HEAD^{commit}')" || die "cannot read the plan branch tip: $BRANCH"
    [ -z "$(cd "$WORKTREE" && cgit status --porcelain)" ] || die "the plan worktree has uncommitted changes (a failed collection?); resolve them first: $WORKTREE"
  elif ls -A "$PLAN" | grep -vqx lock; then
    die "plan dir exists but has no plan.json: $PLAN"
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
```

(The old standalone `umask 077` line is removed; it now sits at the top of this block.)

Also change the line `WORKDIR="$CWD" WORKTREE="" BRANCH="" COMMIT="" COMMIT_FAILED=false RESULT_FILE=/dev/null` so it does not wipe what the plan block loaded:

```bash
WORKDIR="$CWD" COMMIT="" COMMIT_FAILED=false RESULT_FILE=/dev/null
```

(`WORKTREE`, `BRANCH`, `GITDIR`, `GITFILE_HEX` are initialised once in step 4e.)

4g. `write_meta` — add the new fields. Add these `--arg`s to the `jq -n` call:

```bash
    --arg plan_id "$PLAN_ID" --arg plan_dir "$PLAN" --arg job_n "$N" --arg title "$TITLE" \
    --arg resumed_from "$RESUME" --arg parent_commit "$PARENT_COMMIT" \
```

and these keys to the output object, after `commit_failed: $commit_failed, exit_code: $exit_code,`:

```jq
     plan_id: ($plan_id | opt), plan_dir: ($plan_dir | opt),
     job_n: (if $job_n == "" then null else ($job_n | tonumber) end),
     title: ($title | opt), resumed_from: ($resumed_from | opt), parent_commit: ($parent_commit | opt),
```

4h. The `write)` case — replace it with:

```bash
  write)
    if [ "$PLAN_EXISTS" -eq 0 ]; then
      if [ -n "$PLAN" ]; then BRANCH="delegate/$PLAN_ID" WORKTREE="$PLAN/worktree"
      else BRANCH="delegate/$ID" WORKTREE="$JOB/worktree"; fi
      if ! git -C "$TOP" -c core.hooksPath=/dev/null worktree add -q -b "$BRANCH" "$WORKTREE" "$BASE_COMMIT" >> "$JOB/stderr.log" 2>&1; then
        echo "Could not create the git worktree; see stderr.log." > "$JOB/result.md"
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
    FLAGS=(--permission-mode acceptEdits)
    REPORT="$REPORT Work only inside the current directory tree. Do not commit, push or create branches: your file changes are collected and committed for you after you finish."
    ;;
```

4i. Commit message — in the collection block replace `cgit commit -q --no-verify -m "delegate: $ID"` with:

```bash
    if [ -n "$PLAN" ]; then MSG="delegate($PLAN_ID): ${TITLE:-job $N}"; else MSG="delegate: $ID"; fi
    if cgit commit -q --no-verify -m "$MSG" >> "$JOB/stderr.log" 2>&1; then
```

- [ ] **Step 5: Run the new test**

Run: `bash account-delegate/tests/test_delegate_plan.sh; echo "exit $?"`
Expected: only `ok:` lines, `exit 0`.

- [ ] **Step 6: Run the existing suites (must be unchanged)**

Run: `for t in account-delegate/tests/test_delegate.sh account-delegate/tests/test_delegate_write.sh account-delegate/tests/test_watch.sh; do bash "$t" | grep FAIL; echo "$t exit ${PIPESTATUS[0]}"; done`
Expected: no `FAIL` lines; every suite `exit 0`.

- [ ] **Step 7: Commit**

```bash
git add account-delegate/scripts/delegate.sh account-delegate/tests/fake-claude.sh account-delegate/tests/test_delegate_plan.sh
git commit -m "feat(account-delegate): plan mode (--plan, --title) with a shared worktree per plan"
```

---

### Task 2: `--resume` for fix rounds

**Files:**
- Modify: `account-delegate/scripts/delegate.sh`
- Modify: `account-delegate/tests/test_delegate_plan.sh`

**Interfaces:**
- Consumes: from Task 1 — `PLAN`, `PLAN_ID`, `PLAN_EXISTS`, `RESUME` (parsed, only checked to need `--plan`), `FLAGS` array in the `write)` case, fake-claude `FAKE_SESSION`.
- Produces (CLI): `--resume <session_id>`; the claude call gets `--resume <session_id>`; `meta.resumed_from`.

- [ ] **Step 1: Add the failing tests**

In `account-delegate/tests/test_delegate_plan.sh`, insert before the final `rm -rf "$TMP"`:

```bash
# --- --resume
FAKE_MODE=write FAKE_FILE=g.txt FAKE_SESSION=sess-g run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --title "Task 6"
check "a job without --resume does not pass --resume" bash -c '! grep -qxF -- --resume "$1"' _ "$FAKE_LOG/args"
printf 'Fix: rename g.txt contents\n' > "$TMP/fix.md"
FAKE_MODE=write FAKE_FILE=g2.txt FAKE_SESSION=sess-g run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$TMP/fix.md" --resume sess-g --title "Task 6 fix 1"
check "resume run exits 0" test "$CODE" -eq 0
check "claude gets --resume <id>" bash -c 'grep -A1 -xF -- --resume "$1" | tail -n 1 | grep -qx sess-g' _ "$FAKE_LOG/args"
check "fix brief is the new prompt" cmp -s "$TMP/fix.md" "$FAKE_LOG/stdin"
check "meta.resumed_from" test "$(meta .resumed_from)" = sess-g
check "fix round adds a commit" bash -c 'git -C "$1" log -1 --format=%s delegate/p1 | grep -qxF "delegate(p1): Task 6 fix 1"' _ "$REPO"

N_BEFORE="$(njobs "$PLAN")"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --resume nope
check "unknown session exits 2" test "$CODE" -eq 2
FAKE_MODE=write FAKE_FILE=h.txt FAKE_SESSION=sess-other run --mode write --plan "$SPLAN" --cwd "$REPO" --brief "$B"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --resume sess-other
check "foreign session (another plan) exits 2" test "$CODE" -eq 2
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --resume -x
check "--resume starting with a dash exits 2" test "$CODE" -eq 2
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --resume 'a b'
check "--resume with a space exits 2" test "$CODE" -eq 2
check "resume refusals created no job dir" test "$(njobs "$PLAN")" = "$N_BEFORE"
run --mode write --cwd "$REPO" --brief "$B" --base "$MAIN" --resume sess-g
check "--resume without --plan exits 2" test "$CODE" -eq 2
run --mode write --plan "$TMP/plans/p3" --cwd "$REPO" --brief "$B" --base "$MAIN" --resume sess-g
check "--resume on a new plan exits 2" bash -c 'test "$1" -eq 2 && test ! -e "$2/plan.json"' _ "$CODE" "$TMP/plans/p3"
```

- [ ] **Step 2: Run to verify the new checks fail**

Run: `bash account-delegate/tests/test_delegate_plan.sh | grep FAIL`
Expected: at least `FAIL: claude gets --resume <id>` and `FAIL: unknown session exits 2`.

- [ ] **Step 3: Implement**

3a. In the plan flag checks added in Task 1 step 4c, after the `--title` length check, add:

```bash
case "$RESUME" in -*|*[!A-Za-z0-9_-]*) die "invalid --resume: $RESUME" ;; esac
```

3b. In the plan block of Task 1 step 4f, inside `if [ "$PLAN_EXISTS" -eq 1 ]; then`, after the uncommitted-changes check, add:

```bash
    if [ -n "$RESUME" ]; then
      cat "$PLAN"/jobs/*/meta.json 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null | grep -qxF -- "$RESUME" \
        || die "--resume: session $RESUME does not belong to plan $PLAN_ID"
    fi
```

and in the same block's `elif`/new-plan path, refuse `--resume` for a plan that does not exist yet — replace

```bash
  elif ls -A "$PLAN" | grep -vqx lock; then
    die "plan dir exists but has no plan.json: $PLAN"
  fi
```

with

```bash
  else
    [ -z "$RESUME" ] || die "--resume: plan $PLAN_ID has no jobs yet"
    ! ls -A "$PLAN" | grep -vqx lock || die "plan dir exists but has no plan.json: $PLAN"
  fi
```

A refused new plan leaves an empty `$PLAN` dir behind; an empty dir is accepted on the next call.

3c. In the `write)` case, after `FLAGS=(--permission-mode acceptEdits)`, add:

```bash
    [ -z "$RESUME" ] || FLAGS+=(--resume "$RESUME")
```

- [ ] **Step 4: Run all suites**

Run: `for t in account-delegate/tests/test_delegate_plan.sh account-delegate/tests/test_delegate.sh account-delegate/tests/test_delegate_write.sh account-delegate/tests/test_watch.sh; do bash "$t" | grep FAIL; echo "$t exit ${PIPESTATUS[0]}"; done`
Expected: no `FAIL` lines; every suite `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add account-delegate/scripts/delegate.sh account-delegate/tests/test_delegate_plan.sh
git commit -m "feat(account-delegate): --resume a plan job's session for fix rounds"
```

---

### Task 3: One job at a time per plan (`PLAN_DIR/lock`)

**Files:**
- Modify: `account-delegate/scripts/delegate.sh`
- Modify: `account-delegate/tests/test_delegate_plan.sh`

**Interfaces:**
- Consumes: from Task 1 — `PLAN`, `PLAN_ID`, the plan block (step 4f) that starts with `mkdir -p "$PLAN"` / `PLAN="$(cd "$PLAN" && pwd -P)"`.
- Produces: `<PLAN_DIR>/lock/` (dir) with `pid`; released on every exit after it was taken.

- [ ] **Step 1: Add the failing tests**

In `account-delegate/tests/test_delegate_plan.sh`, insert before the final `rm -rf "$TMP"`:

```bash
# --- plan lock
check "no lock left after earlier jobs" test ! -e "$PLAN/lock"
N_BEFORE="$(njobs "$PLAN")"
sleep 30 & HOLDER=$!
mkdir "$PLAN/lock" && echo "$HOLDER" > "$PLAN/lock/pid"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "held lock exits 2" bash -c 'test "$1" -eq 2 && grep -qi "running" "$2"' _ "$CODE" "$TMP/err"
check "held lock: no job dir" test "$(njobs "$PLAN")" = "$N_BEFORE"
check "held lock is left alone" test "$(cat "$PLAN/lock/pid")" = "$HOLDER"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
: > "$PLAN/lock/pid"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "lock with an empty pid exits 2" test "$CODE" -eq 2
echo "$HOLDER" > "$PLAN/lock/pid"   # that process is gone now
FAKE_MODE=ok run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "stale lock is taken over" test "$CODE" -eq 0
check "lock released after the job" test ! -e "$PLAN/lock"
run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B" --base "$MAIN"
check "lock released after a usage error" bash -c 'test "$1" -eq 2 && test ! -e "$2/lock"' _ "$CODE" "$PLAN"
FAKE_MODE=crash run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "crash: exits 1 with meta" bash -c 'test "$1" -eq 1 && test -s "$2/meta.json"' _ "$CODE" "$JOB"
check "crash releases lock" test ! -e "$PLAN/lock"
FAKE_MODE=write FAKE_FILE=i.txt run --mode write --plan "$PLAN" --cwd "$REPO" --brief "$B"
check "next job runs after a crash" test "$CODE" -eq 0
```

Note: the "usage error" case uses `--base` on an existing plan, which is refused in step 4e of Task 1 *before* the lock is taken; it still checks that no lock dir is left behind.

- [ ] **Step 2: Run to verify the new checks fail**

Run: `bash account-delegate/tests/test_delegate_plan.sh | grep FAIL`
Expected: at least `FAIL: held lock exits 2`.

- [ ] **Step 3: Implement**

3a. Next to `pj()` (Task 1 step 4d), add:

```bash
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
```

3b. In the plan block (Task 1 step 4f), call `take_lock` right after `PLAN="$(cd "$PLAN" && pwd -P)"`, before the `if [ "$PLAN_EXISTS" -eq 1 ]` checks.

The existing `trap on_signal TERM INT HUP` is separate from the `EXIT` trap; a signalled job still writes `meta.json` and then exits, which fires `release_lock`.

- [ ] **Step 4: Run all suites**

Run: `for t in account-delegate/tests/test_delegate_plan.sh account-delegate/tests/test_delegate.sh account-delegate/tests/test_delegate_write.sh account-delegate/tests/test_watch.sh; do bash "$t" | grep FAIL; echo "$t exit ${PIPESTATUS[0]}"; done`
Expected: no `FAIL` lines; every suite `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add account-delegate/scripts/delegate.sh account-delegate/tests/test_delegate_plan.sh
git commit -m "feat(account-delegate): plan lock, one job at a time per plan"
```

---

### Task 4: Document plan mode (`SKILL.md`, `README.md`)

**Files:**
- Modify: `account-delegate/SKILL.md`
- Modify: `account-delegate/README.md`

**Interfaces:**
- Consumes: the CLI and files from Tasks 1–3 (`--plan`, `--title`, `--resume`, `plan.json`, `jobs/<n>/`, `lock/`, meta fields `plan_id, plan_dir, job_n, title, resumed_from, parent_commit`).

- [ ] **Step 1: Frontmatter trigger**

In `account-delegate/SKILL.md` frontmatter `description`, after `"delegate this to the other account",` add ` "planı şirket hesabıyla yürüt", "execute this plan on the other account",` and after `the second account is configured.` add ` Also offers to execute a written implementation plan task by task on the second account while this session reviews every task.` (keep it one YAML folded string).

- [ ] **Step 2: Append the "Plan mode" section to `SKILL.md`**

Append at the end of `account-delegate/SKILL.md`:

````markdown
## 6. Plan mode (execute an implementation plan)

The second account writes the code task by task; this session reviews every task itself (no
review subagents: that keeps this account's quota low).

### When to offer

An implementation plan is written (e.g. by `superpowers:writing-plans`), the second account is
configured, the repo is a git repo, and the tasks meet section 1's criteria. This replaces the
usual execution-method question: ask once, e.g.

> Bu planı şirket hesabıyla yürüteyim mi? — kod şirket hesabında, kontrol bende; `develop`
> dalından, 5 görev, görev başına en fazla 3 düzeltme turu. Commit'lenmemiş değişiklikler işe
> görünmez.

Yes covers every task and fix round of this plan. No → `superpowers:subagent-driven-development`.

### Setup

`PLAN_DIR="${DELEGATE_CACHE_DIR:-$HOME/.cache/claude-delegate}/plans/<YYYYMMDD-HHMMSS>-<slug>"`
(slug: `[a-z0-9-]`). Create `PLAN_DIR/progress.md` yourself (the script never touches it):
plan file path, base, and one line per task — status (`pending` / `running` / `done` /
`stopped`), job numbers, session id, fix rounds, cost. Update it after every job.

### Per task

1. **Brief** (scratchpad file, user's language): the task's text copied **verbatim** from the
   plan (the plan file may not be committed on the base, so never just point at it); short
   project context (repo, decisions, things not to touch); one line per finished task; "if you
   cannot run a build or test command, list it under Blocked".
2. **Run** with `run_in_background: true`, then open the side pane as in section 4:

   ```bash
   ~/.claude/skills/account-delegate/scripts/delegate.sh --mode write --plan "<PLAN_DIR>" \
     --cwd "<repo dir>" --brief "<brief file>" --title "Task <n>: <name>" [--base "<base ref>"]
   ```

   `--base` only for the first job of the plan (it creates `PLAN_DIR/plan.json`, the worktree
   `PLAN_DIR/worktree` and branch `delegate/<plan id>`, plan id = basename of `PLAN_DIR`); every
   later job must omit it and pass the same `--cwd`. Exit 2 with no `JOB_DIR=` is a refusal
   (bad flags, held lock, tampered `.git`, worktree not on the plan branch, uncommitted changes
   in the plan worktree): show the message, do not retry blindly.
3. **Review** (this session):
   - Read `<JOB_DIR>/meta.json`; errors and denials → *Stop and ask* below.
   - `git -C <PLAN_DIR>/worktree diff --stat <parent_commit>..<commit>`, then read only the
     relevant hunks (`git -C <PLAN_DIR>/worktree diff <parent_commit>..<commit> -- <paths>`).
     `commit` null with `commit_failed` false means the job changed nothing.
   - Spec compliance first (everything the task asked, nothing more), then code quality.
   - **Safety gate:** if the task's diff touches build, hook, CI or script files
     (`build.gradle*`, `settings.gradle*`, `gradle/`, `package.json`, `Makefile`, `*.sh`,
     `.githooks/`, `.husky/`, `.hooks/`, the `core.hooksPath` dir, `.github/workflows/`,
     `.gitlab-ci.yml`, ...), show those hunks in full and get the user's yes **before** running
     any build or test there. The plan-level yes does not cover this.
   - Run the task's test/verification commands inside `<PLAN_DIR>/worktree`.
4. **Fix round** if anything is wrong: write the findings as a brief and run the same command
   with `--resume <session_id of this task's last job>` and `--title "Task <n> fix <k>"` (no
   `--base`). Then review again. At most 3 fix rounds per task.
5. **Done:** update `progress.md`, tell the user one line (task, rounds, cost), next task.

### Stop and ask

- Still wrong after 3 fix rounds → show the remaining findings; options: you finish it here /
  one more round with a fresh brief and no `--resume` / stop the plan.
- `permission_denials` or a "Blocked" section → list the commands, ask which to run here, run
  only those.
- Job failure (`is_error`, `error_max_turns`, empty `result.md`) → last ~20 formatted events and
  the end of `stderr.log`; options: retry / you do the task here / stop the plan.
- `.git` changed or removed (exit 2 naming `.git`, or `stderr.log` says so) → stop the plan, run
  no git command inside the worktree, leave cleanup to the user as in section 5.
- `commit_failed` true → the worktree holds the only copy; touch nothing, show, ask. The next
  plan job refuses to start until the worktree is clean.
- Safety gate (above).

### End of plan

Summarise: tasks, total cost, total fix rounds. Then follow section 5's write-mode merge rules
with `delegate/<plan id>` as the branch, `plan.json.base` as `base`, `plan.json.base_commit` as
`base_commit` and `<PLAN_DIR>/worktree` as the worktree: `git -C <repo> diff --stat
<base_commit>...delegate/<plan id>`, hook/CI/build hunks in full, "birleştireyim mi?",
`--no-ff`, never switch branches, never `-D` or `--force` unprompted.

### Resuming

After an interruption or `/clear`, read `PLAN_DIR/progress.md` and continue from the first task
that is not `done`. A handoff note names `PLAN_DIR` and `progress.md`.
````

- [ ] **Step 3: Add a "Plan mode" section to `README.md`**

Insert before `## Requirements` in `account-delegate/README.md`:

````markdown
## Plan mode

`delegate.sh --mode write --plan <plan dir> --cwd <dir> --brief <file> [--base <ref>] [--title <t>] [--resume <session id>]`

Runs the tasks of one implementation plan in a single worktree, `<plan dir>/worktree`, on branch
`delegate/<plan id>` (`<plan id>` = basename of `<plan dir>`, `[A-Za-z0-9._-]`). The first call
needs `--base` and writes `<plan dir>/plan.json` (base, base commit, cwd, branch, and the pinned
git dir and `.git` file); later calls refuse `--base` and must use the same `--cwd`. Every call
gets `<plan dir>/jobs/<n>/` (a normal job dir) and adds at most one commit,
`delegate(<plan id>): <title>`. Before a later job starts, the script checks that the `.git`
file is unchanged, that the worktree is on the plan branch and that it has no uncommitted
changes; otherwise it exits 2. `--resume` continues the second account's session of an earlier
job of the same plan (any other session id: exit 2). `<plan dir>/lock` allows one job at a time;
a lock whose process is gone is taken over. The plan worktree is never removed by the script.
`meta.json` gains `plan_id`, `plan_dir`, `job_n`, `title`, `resumed_from` and `parent_commit`
(the branch tip before the job), null outside plan mode. `--plan` is write mode only and cannot
be combined with `--id`; `--title` and `--resume` need `--plan`.
````

and add the new test to the `## Tests` block:

```bash
bash account-delegate/tests/test_delegate_plan.sh
```

- [ ] **Step 4: Verify**

Run: `grep -n "## 6. Plan mode" account-delegate/SKILL.md && grep -n "## Plan mode" account-delegate/README.md && grep -c test_delegate_plan account-delegate/README.md && head -12 account-delegate/SKILL.md`
Expected: both headings found, count `1`, frontmatter still a valid `---` block with the new triggers.

Run: `for t in account-delegate/tests/test_*.sh; do bash "$t" | grep FAIL; echo "$t exit ${PIPESTATUS[0]}"; done`
Expected: no `FAIL` lines; all `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add account-delegate/SKILL.md account-delegate/README.md
git commit -m "docs(account-delegate): plan mode workflow and flags"
```

---

### After all tasks (controller, with the user — not a subagent task)

`~/.claude/CLAUDE.md` is outside the repo. Show the user this proposed change to the
"Plan yürütme yöntemi" bullet and apply it only on their yes:

> … Her zaman **subagent-driven** yolu seç … ; **ancak ikinci hesap tanımlıysa
> (`~/.claude-work`) önce `account-delegate` plan modunu teklif et** ("Bu planı şirket hesabıyla
> yürüteyim mi?"); hayır derse subagent-driven.
