#!/usr/bin/env bash
# Builds the pinned libghostty-vt into vendor/ghostty-vt and copies its headers
# into the CGhosttyVT target. The API is unstable, so the commit is pinned.
set -euo pipefail

GHOSTTY_COMMIT=86aef72a2c8e67c780867de2378b2fc4d6dcd9ca
GHOSTTY_REPO=https://github.com/ghostty-org/ghostty.git

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/ghostty-src"
OUT="$ROOT/vendor/ghostty-vt"
HEADERS="$ROOT/Sources/CGhosttyVT/include/ghostty"

if [[ -f "$OUT/.commit" && "$(cat "$OUT/.commit")" == "$GHOSTTY_COMMIT" && -d "$HEADERS" ]]; then
  echo "libghostty-vt is up to date ($GHOSTTY_COMMIT)"
  exit 0
fi

command -v zig >/dev/null || { echo "zig not found: brew install zig" >&2; exit 1; }

if [[ ! -d "$SRC/.git" ]]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$GHOSTTY_REPO"
fi
git -C "$SRC" fetch -q --depth 1 origin "$GHOSTTY_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD

rm -rf "$OUT"
(cd "$SRC" && zig build -Demit-lib-vt -Doptimize=ReleaseFast --prefix "$OUT")

rm -rf "$HEADERS"
mkdir -p "$(dirname "$HEADERS")"
cp -R "$OUT/include/ghostty" "$HEADERS"

echo "$GHOSTTY_COMMIT" > "$OUT/.commit"
echo "built libghostty-vt at $GHOSTTY_COMMIT"
