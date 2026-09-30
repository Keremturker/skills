#!/usr/bin/env bash
# Build the iosApp for a simulator, install + launch it. Usage: run-ios.sh <projectDir>
set -euo pipefail

DIR="${1:?project dir required}"
if [ "$(uname)" != "Darwin" ] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "SKIP: iOS run needs macOS + Xcode."
  exit 1
fi
cd "$DIR/iosApp"

# Pick a booted simulator, else boot the first available iPhone.
SIM="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
if [ -z "$SIM" ]; then
  SIM="$(xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone .*\(' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
  [ -z "$SIM" ] && { echo "SKIP: no iPhone simulator available."; exit 1; }
  xcrun simctl boot "$SIM" || true
fi
open -a Simulator || true

JH="$(/usr/libexec/java_home -v21 2>/dev/null || true)"; [ -z "$JH" ] && JH="${JAVA_HOME:-}"
JV="$("$JH/bin/java" -version 2>&1 | sed -nE '1s/.*version "([0-9]+).*/\1/p')"
if [ -z "$JV" ] || [ "$JV" -lt 21 ]; then
  echo "SKIP: JAVA_HOME=$JH is JDK ${JV:-unknown}; the iOS build (Kotlin framework) needs JDK 21 or newer."
  exit 1
fi
DD="$(mktemp -d -t cmpios)"
LOG="$(mktemp -t cmpioslog).log"

echo "Building iosApp for the simulator (this is the longest step)…"
if ! JAVA_HOME="$JH" xcodebuild \
    -project iosApp.xcodeproj -scheme iosApp -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM" \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build >"$LOG" 2>&1; then
  echo "iOS BUILD FAILED — last lines:"; tail -25 "$LOG"; exit 1
fi

APP="$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' | head -1)"
[ -z "$APP" ] && { echo "ERROR: .app not found after build."; exit 1; }
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)"

xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" "$BID" || true
echo "OK: launched $BID on simulator $SIM"
echo "    (.app: $APP)"
echo "    (build log: $LOG)"
