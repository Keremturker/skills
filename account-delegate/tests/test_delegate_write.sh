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
check "branch delegate/w1 exists" git -C "$REPO" rev-parse -q --verify refs/heads/delegate/w1
check "change is committed on the branch" bash -c 'git -C "$1" show --name-only --format= delegate/w1 | grep -qx fake.txt' _ "$REPO"
check "commit message" bash -c 'git -C "$1" log -1 --format=%s delegate/w1 | grep -qx "delegate: w1"' _ "$REPO"
check "meta.commit is the branch tip" test "$(meta .commit)" = "$(git -C "$REPO" rev-parse delegate/w1)"
check "meta.branch" test "$(meta .branch)" = delegate/w1
check "meta.commit_failed false" test "$(meta .commit_failed)" = false
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

rm -rf "$TMP"
exit $fail
