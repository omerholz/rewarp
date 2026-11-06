#!/usr/bin/env bash
# Scan source and reachable history without copying ignored local credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v gitleaks >/dev/null || { echo "gitleaks not found: brew install gitleaks" >&2; exit 1; }
gitleaks git . --log-opts="--all --full-history" --redact --no-banner
SOURCE="$(mktemp -d)"
trap 'rm -rf "$SOURCE"' EXIT
python3 - "$SOURCE" <<'PY'
import os
import pathlib
import shutil
import subprocess
import sys

destination = pathlib.Path(sys.argv[1])
paths = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"])
for name in set(paths.split(b"\0")) - {b""}:
    path = pathlib.Path(os.fsdecode(name))
    # Never follow symlinks out of the source tree.
    if path.is_symlink() or not path.is_file():
        continue
    target = destination / path
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, target)
PY
gitleaks dir "$SOURCE" --redact --no-banner
