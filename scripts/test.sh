#!/usr/bin/env bash
# Runs the test suite. Without Xcode, SwiftPM's generated test runner can't see
# the Testing framework unless the flag applies to every target, and it then
# reports success having run nothing. So the path is passed here, and a run that
# doesn't report results is treated as a failure.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# The descriptor-inheritance regression must be able to open a descriptor above
# 255. Raise only the soft limit, before Swift starts any test threads.
OPEN_FILES="$(ulimit -Sn)"
if [[ "$OPEN_FILES" != unlimited && "$OPEN_FILES" -lt 1024 ]]; then
  ulimit -Sn 1024 || { echo 'tests need a soft file limit of at least 1024' >&2; exit 1; }
fi

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LOG="$(mktemp)"
if [[ "$(xcode-select -p)" == */CommandLineTools ]]; then
  REWARP_CLT_TESTING=1 swift test -Xswiftc -F -Xswiftc "$FRAMEWORKS" "$@"
else
  REWARP_CLT_TESTING=0 swift test "$@"
fi 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
if ! grep -Eq 'Test run with [1-9][0-9]* tests? ' "$LOG"; then
  echo "error: the test run reported no executed tests" >&2
  status=1
fi
rm -f "$LOG"
exit "$status"
