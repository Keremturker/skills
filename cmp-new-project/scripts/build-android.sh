#!/usr/bin/env bash
# Verify the generated project compiles for Android. Usage: build-android.sh <projectDir>
set -euo pipefail

DIR="${1:?project dir required}"
cd "$DIR"

JH="$(/usr/libexec/java_home -v21 2>/dev/null || true)"
[ -z "$JH" ] && JH="${JAVA_HOME:-}"
if [ -z "$JH" ]; then
  echo "SKIP: JDK 21 not found (need it for the AGP 9 build). Install JDK 21 and re-run."
  exit 1
fi
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [ ! -d "$SDK" ]; then
  echo "SKIP: Android SDK not found at $SDK."
  exit 1
fi

echo "Building :androidApp:assembleDebug (JDK 21)…"
JAVA_HOME="$JH" ANDROID_HOME="$SDK" ./gradlew :androidApp:assembleDebug --no-configuration-cache

APK="$(find androidApp/build/outputs/apk/debug -name '*.apk' 2>/dev/null | head -1)"
if [ -n "$APK" ]; then
  echo "OK: BUILD SUCCESSFUL → $APK"
else
  echo "ERROR: build finished but no APK was produced."
  exit 1
fi
