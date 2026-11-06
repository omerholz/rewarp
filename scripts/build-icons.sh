#!/usr/bin/env bash
# Rebuild the checked-in macOS icon from its source artwork, using only macOS tools.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET=.build/Rewarp.iconset
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" resources/icons/Rewarp.png \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" resources/icons/Rewarp.png \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o resources/icons/Rewarp.icns
echo "built resources/icons/Rewarp.icns"
