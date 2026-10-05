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
run --mode write --cwd "$TMP/empty-repo" --brief "$TMP/brief.md"
check "repo without commits exits 2" test "$CODE" -eq 2

REPO="$TMP/repo"; mkdir -p "$REPO/sub/dir"
git -C "$REPO" init -q && echo base > "$REPO/README" && echo x > "$REPO/sub/dir/keep" \
  && git -C "$REPO" add . && git -C "$REPO" commit -qm base
echo dirty > "$REPO/uncommitted.txt"

FAKE_MODE=write run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --id w1
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

FAKE_MODE=write run --mode write --cwd "$REPO/sub/dir" --brief "$TMP/brief.md" --id w2
check "subdir: agent runs in the same subdir of the worktree" test "$(cat "$FAKE_LOG/pwd")" = "$(cd "$JOB/worktree/sub/dir" && pwd -P)"
check "subdir: file committed at sub/dir/fake.txt" bash -c 'git -C "$1" show --name-only --format= delegate/w2 | grep -qx sub/dir/fake.txt' _ "$REPO"

FAKE_MODE=ok run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --id w3
check "no changes: exits 0" test "$CODE" -eq 0
check "no changes: meta.commit null" test "$(meta .commit)" = null
check "no changes: branch still at base" test "$(git -C "$REPO" rev-parse delegate/w3)" = "$(git -C "$REPO" rev-parse HEAD)"

FAKE_MODE=crash run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --id w4
check "crash in write mode exits 1 and writes meta" bash -c 'test "$1" -eq 1 && test -s "$2/meta.json"' _ "$CODE" "$JOB"

mkdir -p "$REPO/untracked-dir"
run --mode write --cwd "$REPO/untracked-dir" --brief "$TMP/brief.md" --id w5
check "subdir missing in HEAD exits 2 before creating a job" bash -c 'test "$1" -eq 2 && test -z "$2" && test ! -e "$3/w5"' _ "$CODE" "$JOB" "$DELEGATE_CACHE_DIR"

git -C "$REPO" branch delegate/w6
FAKE_MODE=write run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --id w6
check "worktree add failure exits 1" test "$CODE" -eq 1
check "worktree add failure: meta written, worktree/branch null" bash -c 'jq -e ".worktree == null and .branch == null and .is_error == true" "$1/meta.json" >/dev/null' _ "$JOB"
check "worktree add failure: result.md mentions worktree" grep -qi worktree "$JOB/result.md"

printf '#!/bin/sh\nexit 1\n' > "$REPO/.git/hooks/pre-commit"; chmod +x "$REPO/.git/hooks/pre-commit"
FAKE_MODE=write run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --id w7
check "repo hooks do not run during collection: exits 0" test "$CODE" -eq 0
check "repo hooks do not run during collection: committed" test "$(meta .commit)" = "$(git -C "$REPO" rev-parse delegate/w7)"
rm -f "$REPO/.git/hooks/pre-commit"

FAKE_MODE=lock_index run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --id w8
check "commit failure: exits 0" test "$CODE" -eq 0
check "commit failure: meta.commit_failed true" test "$(meta .commit_failed)" = true
check "commit failure: meta.commit null" test "$(meta .commit)" = null
check "commit failure: change left in the worktree" test -f "$JOB/worktree/fake.txt"
rm -f "$(git -C "$JOB/worktree" rev-parse --absolute-git-dir)/index.lock"

git -C "$REPO" checkout -q --detach
FAKE_MODE=ok run --mode write --cwd "$REPO" --brief "$TMP/brief.md" --id w9
check "detached HEAD: meta.start_branch null" test "$(meta .start_branch)" = null
git -C "$REPO" checkout -q -

# --- agent-controlled git config must not run during collection
HREPO="$TMP/hooked"; mkdir -p "$HREPO/.hooks"
printf '#!/bin/sh\nexit 0\n' > "$HREPO/.hooks/pre-commit"; chmod +x "$HREPO/.hooks/pre-commit"
git -C "$HREPO" init -q && echo base > "$HREPO/README" && git -C "$HREPO" add . \
  && git -C "$HREPO" commit -qm base && git -C "$HREPO" config core.hooksPath .hooks
FAKE_MODE=evil_hook run --mode write --cwd "$HREPO" --brief "$TMP/brief.md" --id h1
check "tracked hook edited by the agent does not run" test ! -e "$FAKE_LOG/hook-ran"
check "tracked hook: change still committed" bash -c 'git -C "$1" show --name-only --format= delegate/h1 | grep -qx fake.txt' _ "$HREPO"
check "tracked hook: meta.commit is the branch tip" test "$(meta .commit)" = "$(git -C "$HREPO" rev-parse delegate/h1)"

FAKE_MODE=evil_gitfile run --mode write --cwd "$HREPO" --brief "$TMP/brief.md" --id h2
check "rewritten .git: fsmonitor of the agent's git dir does not run" test ! -e "$FAKE_LOG/fsmonitor-ran"
check "rewritten .git: exits 0" test "$CODE" -eq 0
check "rewritten .git: meta.commit_failed true" test "$(meta .commit_failed)" = true
check "rewritten .git: meta.commit null" test "$(meta .commit)" = null
check "rewritten .git: branch still at base" test "$(git -C "$HREPO" rev-parse delegate/h2)" = "$(git -C "$HREPO" rev-parse HEAD)"
check "rewritten .git: worktree left in place" test -f "$JOB/worktree/fake.txt"
check "rewritten .git: stderr.log explains" grep -q '\.git' "$JOB/stderr.log"

rm -rf "$TMP"
exit $fail
