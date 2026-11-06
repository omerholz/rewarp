#!/usr/bin/env bash
# Mutation fuzzing of libghostty-vt and PaneSession under Swift/C AddressSanitizer.
set -euo pipefail
cd "$(dirname "$0")/.."
export REWARP_FUZZ_CASES="${REWARP_FUZZ_CASES:-10000}"
GHOSTTY_OPTIMIZE=ReleaseSafe scripts/build-ghostty-vt.sh
scripts/test.sh --scratch-path .build/fuzz --sanitize address --filter TerminalSecurityTests
