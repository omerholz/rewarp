#!/usr/bin/env bash
# Measures how fast a terminal can drain output, by timing a `cat` of a large
# file inside it. Compares Rewarp with the installed Ghostty.
#
# usage: scripts/bench.sh [megabytes] [scroll|repaint]
#   scroll   plain output scrolling past, like `cat` of a log
#   repaint  every cell of the screen rewritten in new colours each frame, the
#            worst case for row caching and the closest to a busy TUI
set -euo pipefail
cd "$(dirname "$0")/.."

MB="${1:-512}"
KIND="${2:-scroll}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 - "$MB" "$WORK/data.txt" "$KIND" <<'PY'
import random, sys
mb, path, kind = int(sys.argv[1]), sys.argv[2], sys.argv[3]
random.seed(1)
def scroll_block():
    line = (b"the quick brown fox \x1b[1;31mjumps\x1b[0m over the lazy dog 0123456789 "
            b"path/to/some/file.swift:42 and some more text to fill out the line\n")
    return line * (1024 * 1024 // len(line) + 1)
def repaint_block():
    words = [b"func", b"let", b"return", b"Block", b"session", b"render", b"cursor", b"output"]
    frames = []
    for _ in range(40):
        rows = [b"\x1b[H"]
        for _ in range(40):
            row = []
            for _ in range(12):
                row.append(b"\x1b[38;5;%dm%-9s" % (random.randrange(16, 231), random.choice(words)))
            rows.append(b"".join(row) + b"\x1b[0m\r\n")
        frames.append(b"".join(rows))
    block = b"".join(frames)
    return block * (1024 * 1024 // len(block) + 1)
block = repaint_block() if kind == "repaint" else scroll_block()
with open(path, "wb") as f:
    for _ in range(mb):
        f.write(block[:1024 * 1024])
PY

cat > "$WORK/inner.sh" <<INNER
#!/bin/bash
stty -echo 2>/dev/null
start=\$(/usr/bin/python3 -c 'import time; print(time.time())')
/bin/cat "$WORK/data.txt"
end=\$(/usr/bin/python3 -c 'import time; print(time.time())')
echo "\$start \$end" > "\$BENCH_RESULT"
INNER
chmod +x "$WORK/inner.sh"
touch "$WORK/.zshrc"

wait_for() {
  local file="$1" pid="$2"
  for _ in $(seq 1 600); do
    [[ -s "$file" ]] && return 0
    kill -0 "$pid" 2>/dev/null || return 1
    /bin/sleep 0.2
  done
  return 1
}

report() {
  python3 - "$1" "$2" "$MB" <<'PY'
import sys
name, path, mb = sys.argv[1], sys.argv[2], int(sys.argv[3])
start, end = map(float, open(path).read().split())
print(f"{name:10} {mb / (end - start):8.0f} MB/s  ({end - start:.2f} s for {mb} MB)")
PY
}

# Keep automation in a separate build directory so it cannot be packaged by
# bundle.sh, which makes its own fresh package build.
swift build --scratch-path .build/bench -c release --product Rewarp -Xswiftc -DREWARP_TESTING 2>&1 | tail -1

for run in 1 2 3; do
  result="$WORK/rewarp-$run"
  # A throwaway HOME, so that the user's startup files can't slow the run down or
  # stop it with a question, such as an update check.
  env -u ZDOTDIR -u HISTFILE -u REWARP_CONTROL -u REWARP_CAPTURE -u REWARP_STATS -u REWARP_SHELL \
    HOME="$WORK" BENCH_RESULT="$result" REWARP_SEND="$WORK/inner.sh" .build/bench/release/Rewarp >/dev/null 2>&1 &
  pid=$!
  wait_for "$result" "$pid" || echo "rewarp run $run did not finish"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  report "Rewarp" "$result"
done

GHOSTTY=/Applications/Ghostty.app/Contents/MacOS/ghostty
if [[ -x "$GHOSTTY" ]]; then
  for run in 1 2 3; do
    result="$WORK/ghostty-$run"
    BENCH_RESULT="$result" "$GHOSTTY" --config-default-files=false --command="$WORK/inner.sh" \
      --quit-after-last-window-closed=true --wait-after-command=false >/dev/null 2>&1 &
    pid=$!
    wait_for "$result" "$pid" || echo "ghostty run $run did not finish"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    [[ -s "$result" ]] && report "Ghostty" "$result"
  done
fi
