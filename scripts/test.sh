#!/usr/bin/env bash
# Runs the test suite. Without Xcode, SwiftPM's generated test runner can't see
# the Testing framework unless the flag applies to every target, and it then
# reports success having run nothing. So the path is passed here, and a run that
# doesn't report results is treated as a failure.
set -uo pipefail
cd "$(dirname "$0")/.."

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LOG="$(mktemp)"
swift test -Xswiftc -F -Xswiftc "$FRAMEWORKS" "$@" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
if ! grep -q 'Test run with' "$LOG"; then
  echo "error: the test run reported no results" >&2
  status=1
fi
rm -f "$LOG"
exit "$status"
