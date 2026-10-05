#!/usr/bin/env bash
# Behavior test for delegate.sh write mode (fake claude). Run: bash account-delegate/tests/test_delegate_write.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
DELEGATE="$HERE/../scripts/delegate.sh"
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok: $d"; else echo "FAIL: $d"; fail=1; fi; }
meta() { jq -r "$1" "$JOB/meta.json"; }
run() { OUT="$(bash "$DELEGATE" "$@" 2>"$TMP/err")"; CODE=$?; JOB="$(sed -n 's/^JOB_DIR=//p' <<<"$OUT" | head -n 1)"; }

TMP="$(mktemp -d)"
export DELEGATE_CLAUDE_BIN="$HERE/fake-claude.sh" DELEGATE_CLAUDE_CONFIG_DIR="$TMP/second" \
       DELEGATE_CACHE_DIR="$TMP/cache" FAKE_LOG="$TMP/log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$DELEGATE_CLAUDE_CONFIG_DIR" "$FAKE_LOG" "$TMP/plain" "$TMP/empty-repo"
printf 'Add fake.txt\n' > "$TMP/brief.md"

run --mode write --cwd "$TMP/plain" --brief "$TMP/brief.md"
check "non-git cwd exits 2" test "$CODE" -eq 2
check "non-git cwd creates no job dir" test -z "$JOB"
git -C "$TMP/empty-repo" init -q
run --mode write --cwd "$TMP/empty-repo" --brief "$TMP/brief.md" --base HEAD
check "repo without commits exits 2" test "$CODE" -eq 2

REPO="$TMP/repo"; mkdir -p "$REPO/sub/dir"
git -C "$REPO" init -q && echo base > "$REPO/README" && echo x > "$REPO/sub/dir/keep" \
  && git -C "$REPO" add . && git -C "$REPO" commit -qm base
MAIN="$(git -C "$REPO" symbolic-ref --short HEAD)"
echo dirty > "$REPO/uncommitted.txt"

FAKE_MODE=write run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --base "$MAIN" --id w1
check "write run exits 0" test "$CODE" -eq 0
check "worktree lives in the job dir" test -d "$JOB/worktree"
check "agent runs in the worktree" test "$(cat "$FAKE_LOG/pwd")" = "$(cd "$JOB/worktree" && pwd -P)"
check "permission mode acceptEdits" bash -c 'grep -A1 -xF -- --permission-mode "$1" | tail -n 1 | grep -qx acceptEdits' _ "$FAKE_LOG/args"
check "no disallowed tools in write mode" bash -c '! grep -qxF -- --disallowedTools "$1"' _ "$FAKE_LOG/args"
check "report says not to commit" bash -c 'grep -qF "Do not commit" "$1"' _ "$FAKE_LOG/args"
check "branch delegate/w1 exists" bash -c 'git -C "$1" rev-parse -q --verify refs/heads/delegate/w1 >/dev/null' _ "$REPO"
check "change is committed on the branch" bash -c 'git -C "$1" show --name-only --format= delegate/w1 | grep -qx fake.txt' _ "$REPO"
check "commit message" bash -c 'git -C "$1" log -1 --format=%s delegate/w1 | grep -qx "delegate: w1"' _ "$REPO"
check "meta.commit is the branch tip" test "$(meta .commit)" = "$(git -C "$REPO" rev-parse delegate/w1)"
check "meta.branch" test "$(meta .branch)" = delegate/w1
check "meta.commit_failed false" test "$(meta .commit_failed)" = false
check "meta.start_branch is the user's branch" test "$(meta .start_branch)" = "$(git -C "$REPO" symbolic-ref --short HEAD)"
check "job dir is private (umask 077)" bash -c 'ls -ld "$1" | grep -q "^drwx------"' _ "$JOB"
check "meta.json is private" bash -c 'ls -l "$1/meta.json" | grep -q "^-rw-------"' _ "$JOB"
check "user's working tree untouched" test ! -e "$REPO/fake.txt"
check "user's uncommitted file still there" test -f "$REPO/uncommitted.txt"
check "uncommitted changes are not visible to the agent" test ! -e "$JOB/worktree/uncommitted.txt"
check "user's branch unchanged" test "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" != delegate/w1

FAKE_MODE=write run --mode write --cwd "$REPO/sub/dir" --brief "$TMP/brief.md" --base "$MAIN" --id w2
check "subdir: agent runs in the same subdir of the worktree" test "$(cat "$FAKE_LOG/pwd")" = "$(cd "$JOB/worktree/sub/dir" && pwd -P)"
check "subdir: file committed at sub/dir/fake.txt" bash -c 'git -C "$1" show --name-only --format= delegate/w2 | grep -qx sub/dir/fake.txt' _ "$REPO"

FAKE_MODE=ok run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --base "$MAIN" --id w3
check "no changes: exits 0" test "$CODE" -eq 0
check "no changes: meta.commit null" test "$(meta .commit)" = null
check "no changes: branch still at base" test "$(git -C "$REPO" rev-parse delegate/w3)" = "$(git -C "$REPO" rev-parse HEAD)"

FAKE_MODE=crash run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --base "$MAIN" --id w4
check "crash in write mode exits 1 and writes meta" bash -c 'test "$1" -eq 1 && test -s "$2/meta.json"' _ "$CODE" "$JOB"

mkdir -p "$REPO/untracked-dir"
run --mode write --cwd "$REPO/untracked-dir" --brief "$TMP/brief.md" --base "$MAIN" --id w5
check "subdir missing on base exits 2 before creating a job" bash -c 'test "$1" -eq 2 && test -z "$2" && test ! -e "$3/w5"' _ "$CODE" "$JOB" "$DELEGATE_CACHE_DIR"

git -C "$REPO" branch delegate/w6
FAKE_MODE=write run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --base "$MAIN" --id w6
check "worktree add failure exits 1" test "$CODE" -eq 1
check "worktree add failure: meta written, worktree/branch null" bash -c 'jq -e ".worktree == null and .branch == null and .is_error == true" "$1/meta.json" >/dev/null' _ "$JOB"
check "worktree add failure: result.md mentions worktree" grep -qi worktree "$JOB/result.md"

printf '#!/bin/sh\nexit 1\n' > "$REPO/.git/hooks/pre-commit"; chmod +x "$REPO/.git/hooks/pre-commit"
FAKE_MODE=write run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --base "$MAIN" --id w7
check "repo hooks do not run during collection: exits 0" test "$CODE" -eq 0
check "repo hooks do not run during collection: committed" test "$(meta .commit)" = "$(git -C "$REPO" rev-parse delegate/w7)"
rm -f "$REPO/.git/hooks/pre-commit"

FAKE_MODE=lock_index run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --base "$MAIN" --id w8
check "commit failure: exits 0" test "$CODE" -eq 0
check "commit failure: meta.commit_failed true" test "$(meta .commit_failed)" = true
check "commit failure: meta.commit null" test "$(meta .commit)" = null
check "commit failure: change left in the worktree" test -f "$JOB/worktree/fake.txt"
rm -f "$(git -C "$JOB/worktree" rev-parse --absolute-git-dir)/index.lock"

git -C "$REPO" checkout -q --detach
FAKE_MODE=ok run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --base "$MAIN" --id w9
check "detached HEAD: meta.start_branch null" test "$(meta .start_branch)" = null
git -C "$REPO" checkout -q -

# --- --base: the job starts from the named ref, never from the user's HEAD
BREPO="$TMP/brepo"; mkdir -p "$BREPO/shared"
git -C "$BREPO" init -q && echo m > "$BREPO/shared/m.txt" && git -C "$BREPO" add . && git -C "$BREPO" commit -qm main1
BMAIN="$(git -C "$BREPO" symbolic-ref --short HEAD)"
git -C "$BREPO" checkout -q -b other && mkdir "$BREPO/onlyother" && echo o > "$BREPO/onlyother/o.txt" \
  && echo o > "$BREPO/other.txt" && git -C "$BREPO" add . && git -C "$BREPO" commit -qm other1
OTHER_SHA="$(git -C "$BREPO" rev-parse HEAD)"
git -C "$BREPO" tag v1 && git -C "$BREPO" checkout -q "$BMAIN"
mkdir "$BREPO/mainonly" && echo x > "$BREPO/mainonly/x.txt" && git -C "$BREPO" add . && git -C "$BREPO" commit -qm main2
MAIN_SHA="$(git -C "$BREPO" rev-parse HEAD)"
mkdir "$BREPO/onlyother"   # exists on disk (empty) but is not tracked on the user's branch

run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --id b0
check "git repo without --base exits 2 with no job dir" bash -c 'test "$1" -eq 2 && test -z "$2" && test ! -e "$3/b0"' _ "$CODE" "$JOB" "$DELEGATE_CACHE_DIR"
run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base no-such-ref --id b0
check "invalid --base exits 2 with no job dir" bash -c 'test "$1" -eq 2 && test -z "$2" && test ! -e "$3/b0"' _ "$CODE" "$JOB" "$DELEGATE_CACHE_DIR"
run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base -x --id b0
check "--base starting with a dash exits 2 with the specific message" bash -c 'test "$1" -eq 2 && grep -q "invalid --base" "$2" && test ! -e "$3/b0"' _ "$CODE" "$TMP/err" "$DELEGATE_CACHE_DIR"
git -C "$BREPO" branch amb && git -C "$BREPO" tag amb
run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base amb --id b0
check "base that is both a branch and a tag exits 2 (ambiguous)" bash -c 'test "$1" -eq 2 && grep -qi ambiguous "$2" && test ! -e "$3/b0"' _ "$CODE" "$TMP/err" "$DELEGATE_CACHE_DIR"
git -C "$BREPO" tag -d amb >/dev/null; git -C "$BREPO" branch -D amb >/dev/null
run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base "" --id b0
check "empty --base exits 2" bash -c 'test "$1" -eq 2 && test ! -e "$2/b0"' _ "$CODE" "$DELEGATE_CACHE_DIR"
run --mode write --cwd "$TMP/plain" --brief "$TMP/brief.md" --base "$BMAIN" --id b0
check "write with --base but non-git cwd exits 2" test "$CODE" -eq 2

HEAD_BEFORE="$(git -C "$BREPO" rev-parse HEAD)"; STATUS_BEFORE="$(git -C "$BREPO" status --porcelain)"
FAKE_MODE=write run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base other --id b1
check "write from another branch exits 0" test "$CODE" -eq 0
check "agent runs in the worktree" test "$(cat "$FAKE_LOG/pwd")" = "$(cd "$JOB/worktree" && pwd -P)"
check "file that exists only on the base is visible in the worktree" test -f "$JOB/worktree/other.txt"
check "file only on the user's branch is not in the worktree" test ! -e "$JOB/worktree/mainonly"
check "commit parent is the tip of the base" test "$(git -C "$BREPO" rev-parse delegate/b1^)" = "$OTHER_SHA"
check "user's current branch unchanged" test "$(git -C "$BREPO" symbolic-ref --short HEAD)" = "$BMAIN"
check "user's HEAD commit unchanged" test "$(git -C "$BREPO" rev-parse HEAD)" = "$HEAD_BEFORE"
check "user's tree unchanged" test "$(git -C "$BREPO" status --porcelain)" = "$STATUS_BEFORE"
check "meta.base as given" test "$(meta .base)" = other
check "meta.base_commit is the resolved sha" test "$(meta .base_commit)" = "$OTHER_SHA"
check "meta.start_branch is the user's branch" test "$(meta .start_branch)" = "$BMAIN"

FAKE_MODE=write run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base v1 --id b2
check "write with a tag base: exits 0" test "$CODE" -eq 0
check "tag base: meta.base as given, base_commit resolved" bash -c 'test "$(jq -r .base "$1/meta.json")" = v1 && test "$(jq -r .base_commit "$1/meta.json")" = "$2"' _ "$JOB" "$OTHER_SHA"
check "tag base: commit parent is the tagged commit" test "$(git -C "$BREPO" rev-parse delegate/b2^)" = "$OTHER_SHA"
FAKE_MODE=write run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base "$MAIN_SHA" --id b3
check "write with a sha base: exits 0" test "$CODE" -eq 0
check "sha base: meta.base as given" test "$(meta .base)" = "$MAIN_SHA"
check "sha base: commit parent is that sha" test "$(git -C "$BREPO" rev-parse delegate/b3^)" = "$MAIN_SHA"

FAKE_MODE=write run --mode write --cwd "$BREPO/onlyother" --brief "$TMP/brief.md" --base other --id b4
check "subdir that exists on the base but not on HEAD is allowed" test "$CODE" -eq 0
check "that subdir: agent runs in it inside the worktree" test "$(cat "$FAKE_LOG/pwd")" = "$(cd "$JOB/worktree/onlyother" && pwd -P)"
run --mode write --cwd "$BREPO/mainonly" --brief "$TMP/brief.md" --base other --id b5
check "subdir missing on the base exits 2 with no job dir" bash -c 'test "$1" -eq 2 && test -z "$2" && test ! -e "$3/b5"' _ "$CODE" "$JOB" "$DELEGATE_CACHE_DIR"

git -C "$BREPO" checkout -q -b rfile "$BMAIN" && echo f > "$BREPO/fileonbase" && git -C "$BREPO" add fileonbase && git -C "$BREPO" commit -qm file \
  && git -C "$BREPO" checkout -q "$BMAIN" && mkdir "$BREPO/fileonbase"
run --mode write --cwd "$BREPO/fileonbase" --brief "$TMP/brief.md" --base rfile --id b7
check "--cwd that is a file on the base exits 2 with no job dir" bash -c 'test "$1" -eq 2 && test -z "$2" && test ! -e "$3/b7"' _ "$CODE" "$JOB" "$DELEGATE_CACHE_DIR"

# worktree add must not run the user's post-checkout hook
printf '#!/bin/sh\ntouch "%s"\n' "$FAKE_LOG/post-checkout-ran" > "$BREPO/.git/hooks/post-checkout"; chmod +x "$BREPO/.git/hooks/post-checkout"
FAKE_MODE=write run --mode write --cwd "$BREPO" --brief "$TMP/brief.md" --base "$BMAIN" --id b6
check "user's post-checkout hook does not run for the worktree" bash -c 'test "$1" -eq 0 && test ! -e "$2/post-checkout-ran"' _ "$CODE" "$FAKE_LOG"
rm -f "$BREPO/.git/hooks/post-checkout"

# --- agent-controlled git config must not run during collection
HREPO="$TMP/hooked"; mkdir -p "$HREPO/.hooks"
printf '#!/bin/sh\nexit 0\n' > "$HREPO/.hooks/pre-commit"; chmod +x "$HREPO/.hooks/pre-commit"
git -C "$HREPO" init -q && echo base > "$HREPO/README" && git -C "$HREPO" add . \
  && git -C "$HREPO" commit -qm base && git -C "$HREPO" config core.hooksPath .hooks
HMAIN="$(git -C "$HREPO" symbolic-ref --short HEAD)"
FAKE_MODE=evil_hook run --mode write --cwd "$HREPO" --brief "$TMP/brief.md" --base "$HMAIN" --id h1
check "tracked hook edited by the agent does not run" test ! -e "$FAKE_LOG/hook-ran"
check "tracked hook: change still committed" bash -c 'git -C "$1" show --name-only --format= delegate/h1 | grep -qx fake.txt' _ "$HREPO"
check "tracked hook: meta.commit is the branch tip" test "$(meta .commit)" = "$(git -C "$HREPO" rev-parse delegate/h1)"

FAKE_MODE=evil_gitfile run --mode write --cwd "$HREPO" --brief "$TMP/brief.md" --base "$HMAIN" --id h2
check "rewritten .git: fsmonitor of the agent's git dir does not run" test ! -e "$FAKE_LOG/fsmonitor-ran"
check "rewritten .git: exits 0" test "$CODE" -eq 0
check "rewritten .git: meta.commit_failed true" test "$(meta .commit_failed)" = true
check "rewritten .git: meta.commit null" test "$(meta .commit)" = null
check "rewritten .git: branch still at base" test "$(git -C "$HREPO" rev-parse delegate/h2)" = "$(git -C "$HREPO" rev-parse HEAD)"
check "rewritten .git: worktree left in place" test -f "$JOB/worktree/fake.txt"
check "rewritten .git: stderr.log explains" grep -q '\.git' "$JOB/stderr.log"

rm -rf "$TMP"
exit $fail
