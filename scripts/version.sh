#!/usr/bin/env bash
# Prints the version set in Version.swift, for packaging.
set -euo pipefail
sed -n 's/.*static let string = "\(.*\)"/\1/p' "$(dirname "$0")/../Sources/RewarpCore/Version.swift"
