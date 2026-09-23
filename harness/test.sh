#!/bin/bash
# Canonical simulator test runner. It uses a dedicated device so test launches
# never touch a developer's workout history. Boot explicitly: Xcode sometimes
# waits for a shut-down simulator instead of starting it, which makes
# `xcodebuild test` look hung even though the scheme is valid.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED_DATA="${LOKT_TEST_DERIVED_DATA:-/tmp/lokt-simulator-tests}"
TEST_DEVICE_NAME="${LOKT_TEST_DEVICE_NAME:-Lokt Tests iPhone 16 Pro}"

if [ -n "${LOKT_TEST_DEVICE_ID:-}" ]; then
  DEVICE_ID="$LOKT_TEST_DEVICE_ID"
else
  DEVICE_ID=$(xcrun simctl list devices available | awk -v device="$TEST_DEVICE_NAME" '
    /^-- iOS 18\.5 --/ { in_runtime = 1; next }
    /^-- / { in_runtime = 0 }
    in_runtime && index($0, "    " device " (") == 1 {
      id = $0
      sub("^[[:space:]]*" device " \\(", "", id)
      sub(/\).*/, "", id)
      print id
      exit
    }
  ')

  if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun simctl create "$TEST_DEVICE_NAME" \
      com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
      com.apple.CoreSimulator.SimRuntime.iOS-18-5)
  fi
fi

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b

xcodebuild test \
  -project "LockIn Set Tracker.xcodeproj" \
  -scheme "LockIn Set Tracker" \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -parallel-testing-enabled NO \
  -only-testing:"LockIn Set TrackerTests"
