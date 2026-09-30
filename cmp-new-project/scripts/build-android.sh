#!/usr/bin/env bash
# Verify the generated project builds for Android, that its unit tests pass on the JVM (Android
# host) when the project has any, and, when the project has detekt, that detekt is clean. Runs
# with the project's own configuration cache (on in gradle.properties), so cache regressions show
# up here too. Usage: build-android.sh <projectDir>
set -euo pipefail

DIR="${1:?project dir required}"
cd "$DIR"

JH="$(/usr/libexec/java_home -v21 2>/dev/null || true)"
[ -z "$JH" ] && JH="${JAVA_HOME:-}"
if [ -z "$JH" ]; then
  echo "SKIP: JDK 21 not found (need it for the AGP 9 build). Install JDK 21 and re-run."
  exit 1
fi
JV="$("$JH/bin/java" -version 2>&1 | sed -nE '1s/.*version "([0-9]+).*/\1/p' || true)"
if [ -z "$JV" ] || [ "$JV" -lt 21 ]; then
  echo "SKIP: JAVA_HOME=$JH is JDK ${JV:-unknown}; the build needs JDK 21 or newer. Install JDK 21 and re-run."
  exit 1
fi
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [ ! -d "$SDK" ]; then
  echo "SKIP: Android SDK not found at $SDK."
  exit 1
fi

echo "Building :androidApp:assembleDebug (JDK $JV)…"
JAVA_HOME="$JH" ANDROID_HOME="$SDK" ./gradlew :androidApp:assembleDebug

APK="$(find androidApp/build/outputs/apk/debug -name '*.apk' 2>/dev/null | head -1)"
if [ -n "$APK" ]; then
  echo "OK: BUILD SUCCESSFUL → $APK"
else
  echo "ERROR: build finished but no APK was produced."
  exit 1
fi

# Unit tests and detekt both run, so one red result does not hide the other; fail at the end.
FAILED=0

# Templates with tests ship shared/src/androidHostTest, among them KoinGraphTest (every Koin
# dependency defined); projects from older templates have none.
if [ -d shared/src/androidHostTest ]; then
  echo "Running unit tests (Android host)…"
  if JAVA_HOME="$JH" ANDROID_HOME="$SDK" ./gradlew testAndroidHostTest --continue; then
    echo "OK: UNIT TESTS PASS"
  else
    echo "ERROR: unit tests failed (the FAILED lines above). A KoinGraphTest failure names the type no Koin module defines."
    FAILED=1
  fi
else
  echo "unit tests: none in this project (generated before the template had tests), skipped."
fi

# Only projects generated with detekt have the convention plugin (and so a detekt task).
if [ -f build-logic/src/main/kotlin/convention/DetektConventionPlugin.kt ]; then
  echo "Running detekt…"
  if JAVA_HOME="$JH" ANDROID_HOME="$SDK" ./gradlew detekt --continue; then
    echo "OK: DETEKT CLEAN"
  else
    echo "ERROR: detekt found issues (the e: lines above). Fix them with the cmp-detekt skill."
    FAILED=1
  fi
else
  echo "detekt: not enabled in this project, skipped."
fi

exit "$FAILED"
