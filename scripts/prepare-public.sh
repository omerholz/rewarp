#!/usr/bin/env bash
# Export reviewed source into a new repository without old refs or objects.
# Usage: scripts/prepare-public.sh /absolute/path/outside/this/repo
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 ]] || { echo "usage: $0 /absolute/path/to/new-repo" >&2; exit 1; }
DESTINATION="$1"
python3 - "$DESTINATION" <<'PY'
import os
import pathlib
import shutil
import subprocess
import sys

source = pathlib.Path.cwd().resolve()
destination = pathlib.Path(sys.argv[1])
if not destination.is_absolute():
    sys.exit("destination must be absolute")
destination = destination.resolve()
if destination == source or source in destination.parents:
    sys.exit("destination must be outside the source repository")
if destination.exists():
    sys.exit("destination must not already exist")
paths = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"])
destination.mkdir(parents=True)
for name in sorted(set(paths.split(b"\0")) - {b""}):
    path = pathlib.Path(os.fsdecode(name))
    if not path.is_file() and not path.is_symlink():
        continue
    target = destination / path
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        target.symlink_to(os.readlink(path))
    else:
        shutil.copy2(path, target)
PY
git -C "$DESTINATION" init -q -b main
git -C "$DESTINATION" add --all
GIT_AUTHOR_NAME=omerholz GIT_AUTHOR_EMAIL=2319152+omerholz@users.noreply.github.com \
GIT_COMMITTER_NAME=omerholz GIT_COMMITTER_EMAIL=2319152+omerholz@users.noreply.github.com \
git -C "$DESTINATION" -c user.name=omerholz -c user.email=2319152+omerholz@users.noreply.github.com \
  -c commit.gpgsign=false commit -q -m "Initial public release"
echo "Prepared $DESTINATION with one commit on main and no remote."
echo "Review its contents and run make secrets before publishing."
