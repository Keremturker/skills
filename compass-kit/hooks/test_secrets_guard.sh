#!/bin/sh
# Behavior test for secrets-guard.py. Run: sh compass-kit/hooks/test_secrets_guard.sh
HOOK="$(dirname "$0")/secrets-guard.py"
fail=0
expect() { # $1 = expected exit code, $2 = description, $3 = hook input (JSON)
  printf '%s' "$3" | python3 "$HOOK" >/dev/null 2>&1; code=$?
  if [ "$code" != "$1" ]; then echo "FAIL ($code != $1): $2"; fail=1; else echo "ok: $2"; fi
}
expect 2 "Google API key is blocked" '{"tool_name":"Write","tool_input":{"file_path":"/p/shared/src/commonMain/kotlin/Api.kt","content":"val key = \"AIzaSyA1234567890abcdefghijklmnopqrstuv\""}}'
expect 2 "private key header is blocked" '{"tool_name":"Edit","tool_input":{"file_path":"/p/core/Net.kt","old_string":"x","new_string":"-----BEGIN PRIVATE KEY-----"}}'
expect 2 "AWS access key is blocked" '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Aws.kt","content":"AKIAABCDEFGHIJKLMNOP"}}'
expect 2 "connection string with a password is blocked" '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Db.kt","content":"postgres://user:hunter2@db.example.com/app"}}'
expect 2 "GitHub token is blocked" '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Gh.kt","content":"ghp_abcdefghijklmnopqrstuvwxyz0123456789"}}'
expect 2 "plain-text keystore password is blocked" '{"tool_name":"Write","tool_input":{"file_path":"/p/keystore.properties","content":"storePassword=gizli123"}}'
expect 0 "markdown is allowed" '{"tool_name":"Write","tool_input":{"file_path":"/p/README.md","content":"AIzaSyA1234567890abcdefghijklmnopqrstuv"}}'
expect 0 "test fixture is allowed" '{"tool_name":"Write","tool_input":{"file_path":"/p/core/src/commonTest/kotlin/FakeTest.kt","content":"AKIAABCDEFGHIJKLMNOP"}}'
expect 0 "writing local.properties is allowed" '{"tool_name":"Write","tool_input":{"file_path":"/p/local.properties","content":"sdk.dir=/Users/k/Library/Android/sdk"}}'
expect 0 "ordinary code is allowed" '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Ui.kt","content":"val title = \"Merhaba\""}}'
expect 2 "staging local.properties is blocked" '{"tool_name":"Bash","tool_input":{"command":"git add local.properties"}}'
expect 2 "staging a .jks file is blocked" '{"tool_name":"Bash","tool_input":{"command":"git add keystores/app.jks && git commit -m x"}}'
expect 2 "--no-verify is blocked" '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}'
expect 0 "ordinary staging is allowed" '{"tool_name":"Bash","tool_input":{"command":"git add shared/src/commonMain/kotlin/App.kt"}}'
expect 0 "gradlew is allowed" '{"tool_name":"Bash","tool_input":{"command":"./gradlew :androidApp:assembleDebug"}}'
expect 0 "broken input fails open" 'bozuk json'
exit $fail
