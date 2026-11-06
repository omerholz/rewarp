#!/usr/bin/env bash
# Builds the pinned libghostty-vt into vendor/ghostty-vt and copies its headers
# into the CGhosttyVT target. The API is unstable, so the commit is pinned.
set -euo pipefail

GHOSTTY_REPO=https://github.com/ghostty-org/ghostty.git

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/ghostty-version.env"
OPTIMIZE="${GHOSTTY_OPTIMIZE:-ReleaseSafe}"
case "$OPTIMIZE" in
  Debug|ReleaseSafe|ReleaseFast|ReleaseSmall) ;;
  *) echo "invalid GHOSTTY_OPTIMIZE: $OPTIMIZE" >&2; exit 1 ;;
esac
SRC="$ROOT/vendor/ghostty-src"
OUT="$ROOT/vendor/ghostty-vt"
HEADERS="$ROOT/Sources/CGhosttyVT/include/ghostty"

command -v zig >/dev/null || { echo "zig not found: brew install zig" >&2; exit 1; }
ACTUAL_ZIG_VERSION="$(zig version)"
[[ "$ACTUAL_ZIG_VERSION" == "$ZIG_VERSION" ]] || {
  echo "libghostty-vt needs Zig $ZIG_VERSION; found $ACTUAL_ZIG_VERSION" >&2; exit 1;
}
BUILD_KEY="$GHOSTTY_COMMIT $ACTUAL_ZIG_VERSION $OPTIMIZE $(uname -sm)"
if [[ -f "$OUT/.build-key" && "$(cat "$OUT/.build-key")" == "$BUILD_KEY" &&
      -f "$OUT/lib/libghostty-vt.a" && -f "$HEADERS/vt.h" ]]; then
  echo "libghostty-vt is up to date ($BUILD_KEY)"
  exit 0
fi

if [[ ! -d "$SRC/.git" ]]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$GHOSTTY_REPO"
fi
git -C "$SRC" fetch -q --depth 1 origin "$GHOSTTY_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD

rm -rf "$OUT"
(cd "$SRC" && zig build -Demit-lib-vt -Doptimize="$OPTIMIZE" --prefix "$OUT")

rm -rf "$HEADERS"
mkdir -p "$(dirname "$HEADERS")"
cp -R "$OUT/include/ghostty" "$HEADERS"

echo "$GHOSTTY_COMMIT" > "$OUT/.commit"
echo "$BUILD_KEY" > "$OUT/.build-key"
echo "built libghostty-vt ($BUILD_KEY)"
