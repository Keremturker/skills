#!/usr/bin/env bash
# Stand-in for `claude` in tests: records how it was called and prints a canned stream-json run.
printf '%s\n' "$@" > "$FAKE_LOG/args"
cat > "$FAKE_LOG/stdin"
pwd -P > "$FAKE_LOG/pwd"
printf '%s\n' "${CLAUDE_CONFIG_DIR:-}" > "$FAKE_LOG/config"
env > "$FAKE_LOG/env"
echo '{"type":"system","subtype":"init","model":"fake","cwd":"x"}'
case "${FAKE_MODE:-ok}" in
  ok)
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"a"}}]}}'
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.3,"session_id":"s1","permission_denials":[],"result":"## Done\nAll done."}'
    ;;
  write)
    echo hello > fake.txt
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.1,"session_id":"s2","permission_denials":[],"result":"wrote fake.txt"}'
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
esac
