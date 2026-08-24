#!/bin/bash
# Canonical build. The destination MUST pin OS=18.5: the active Xcode ships
# iOS 18.5 and 26.5 simulators under identical names, and an unpinned
# "iPhone 16" fails destination matching (this bit us once — hence this script).
set -uo pipefail
cd "$(dirname "$0")/.."

LOG=$(mktemp)
xcodebuild -scheme "LockIn Set Tracker" \
  -project "LockIn Set Tracker.xcodeproj" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  build >"$LOG" 2>&1
STATUS=$?

if [ $STATUS -eq 0 ] && grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "BUILD SUCCEEDED"
else
  echo "BUILD FAILED — errors:"
  grep -E "error:" "$LOG" | head -20
fi
rm -f "$LOG"
exit $STATUS
