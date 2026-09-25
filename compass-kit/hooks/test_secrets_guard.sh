#!/bin/sh
# secrets-guard.py'nin davranış testi. Çalıştır: sh compass-kit/hooks/test_secrets_guard.sh
HOOK="$(dirname "$0")/secrets-guard.py"
fail=0
expect() { # $1 = beklenen çıkış kodu, $2 = açıklama, stdin = hook girdisi
  python3 "$HOOK" >/dev/null 2>&1; code=$?
  if [ "$code" != "$1" ]; then echo "FAIL ($code != $1): $2"; fail=1; else echo "ok: $2"; fi
}
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/shared/src/commonMain/kotlin/Api.kt","content":"val key = \"AIzaSyA1234567890abcdefghijklmnopqrstuv\""}}' | expect 2 "Google API anahtarı engellenir"
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/p/core/Net.kt","old_string":"x","new_string":"-----BEGIN PRIVATE KEY-----"}}' | expect 2 "private key başlığı engellenir"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Aws.kt","content":"AKIAABCDEFGHIJKLMNOP"}}' | expect 2 "AWS erişim anahtarı engellenir"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Db.kt","content":"postgres://user:hunter2@db.example.com/app"}}' | expect 2 "parolalı bağlantı adresi engellenir"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Gh.kt","content":"ghp_abcdefghijklmnopqrstuvwxyz0123456789"}}' | expect 2 "GitHub token engellenir"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/keystore.properties","content":"storePassword=gizli123"}}' | expect 2 "düz metin keystore parolası engellenir"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/README.md","content":"AIzaSyA1234567890abcdefghijklmnopqrstuv"}}' | expect 0 "markdown serbest"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/core/src/commonTest/kotlin/FakeTest.kt","content":"AKIAABCDEFGHIJKLMNOP"}}' | expect 0 "test fixture serbest"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/local.properties","content":"sdk.dir=/Users/k/Library/Android/sdk"}}' | expect 0 "local.properties yazmak serbest"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/core/Ui.kt","content":"val title = \"Merhaba\""}}' | expect 0 "sıradan kod serbest"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git add local.properties"}}' | expect 2 "local.properties stage engellenir"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git add keystores/app.jks && git commit -m x"}}' | expect 2 "jks stage engellenir"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' | expect 2 "--no-verify engellenir"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git add shared/src/commonMain/kotlin/App.kt"}}' | expect 0 "sıradan stage serbest"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"./gradlew :androidApp:assembleDebug"}}' | expect 0 "gradlew serbest"
printf '%s' 'bozuk json' | expect 0 "bozuk girdi fail-open"
exit $fail
