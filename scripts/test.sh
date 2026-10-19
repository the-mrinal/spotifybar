#!/bin/sh
# Runs the unit tests; pass extra xcodebuild args (e.g. -only-testing:SpotifyBarCoreTests/APIDecodingTests).
set -eu
cd "$(dirname "$0")/.."
xcodegen generate -q
LOG=build/test.log
mkdir -p build
if xcodebuild -scheme SpotifyBar -destination 'platform=macOS' -derivedDataPath build test "$@" >"$LOG" 2>&1; then
  grep -E "Test run with|tests? passed|TEST SUCCEEDED" "$LOG" | tail -3
else
  grep -E "error:|✘|failed|recorded an issue" "$LOG" | head -40
  tail -3 "$LOG"
  exit 1
fi
