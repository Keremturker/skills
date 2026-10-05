#!/usr/bin/env bash
# Stand-in for `claude` in tests: records how it was called and prints a canned stream-json run.
echo $$ > "$FAKE_LOG/pid"
printf '%s\n' "$@" > "$FAKE_LOG/args"
cat > "$FAKE_LOG/stdin"
pwd -P > "$FAKE_LOG/pwd"
ls -A > "$FAKE_LOG/ls"
printf '%s\n' "${CLAUDE_CONFIG_DIR:-}" > "$FAKE_LOG/config"
env > "$FAKE_LOG/env"
echo '{"type":"system","subtype":"init","model":"fake","cwd":"x"}'
case "${FAKE_MODE:-ok}" in
  ok)
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"a"}}]}}'
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.3,"session_id":"s1","permission_denials":[],"result":"## Done\nAll done."}'
    ;;
  write)
    echo hello > "${FAKE_FILE:-fake.txt}"
    printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.1,"session_id":"%s","permission_denials":[],"result":"wrote %s"}\n' \
      "${FAKE_SESSION:-s2}" "${FAKE_FILE:-fake.txt}"
    ;;
  dirty_ro)   # leaves an untracked file, so `git worktree remove` refuses
    echo junk > junk.txt
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"ok"}'
    ;;
  is_error)
    echo '{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":40,"total_cost_usd":1.5,"session_id":"s3","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"git push"}}]}'
    ;;
  crash)
    echo boom >&2
    exit 3
    ;;
  sleep)
    exec sleep 30
    ;;
  evil_hook)   # rewrites a tracked git hook (core.hooksPath=.hooks) to leave a marker
    echo hello > fake.txt
    printf '#!/bin/sh\ntouch "%s"\n' "$FAKE_LOG/hook-ran" > .hooks/pre-commit
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"edited hook"}'
    ;;
  evil_gitfile)   # points the worktree's .git file at a git dir it built, with core.fsmonitor
    echo hello > fake.txt
    git init -q .evil
    git -C .evil config core.fsmonitor "touch '$FAKE_LOG/fsmonitor-ran'; false"
    printf 'gitdir: %s\n' "$PWD/.evil/.git" > .git
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"rewrote .git"}'
    ;;
  lock_index)   # makes the collection's `git add` fail
    echo hello > fake.txt
    : > "$(git rev-parse --git-dir)/index.lock"
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"locked"}'
    ;;
  nested_filter)   # a nested repo whose own config sets a clean filter that leaves a marker
    mkdir nested && (cd nested && git init -q && echo a > f && echo '* filter=ev' > .gitattributes \
      && git add -A && git -c user.name=x -c user.email=x@x commit -qm n \
      && git config filter.ev.clean "touch '$FAKE_LOG/filter-ran'; cat")
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"nested repo"}'
    ;;
  big)   # a ~2 MB final report
    printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"%s"}\n' \
      "$(head -c 2000000 /dev/zero | tr '\0' x)"
    ;;
esac
