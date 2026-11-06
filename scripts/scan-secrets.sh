#!/usr/bin/env bash
# Scan every commit reachable from the locally fetched refs. Never print secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
  echo 'full-history scanning requires an unshallow checkout (fetch-depth: 0 in CI)' >&2
  exit 1
fi
if command -v gitleaks >/dev/null; then
  GITLEAKS="$(command -v gitleaks)"
else
  [[ "$(uname -sm)" == 'Linux x86_64' ]] || {
    echo 'install gitleaks, then rerun scripts/scan-secrets.sh' >&2; exit 1;
  }
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  curl --fail --location --retry 3 --output "$WORK/gitleaks.tar.gz" \
    https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
  printf '%s  %s\n' 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb \
    "$WORK/gitleaks.tar.gz" | sha256sum --check
  tar -xzf "$WORK/gitleaks.tar.gz" -C "$WORK" gitleaks
  GITLEAKS="$WORK/gitleaks"
fi
"$GITLEAKS" git --no-banner --redact --log-opts='--all --full-history' .
# Uncommitted and newly added files are also checked during local runs.
"$GITLEAKS" dir --no-banner --redact .
