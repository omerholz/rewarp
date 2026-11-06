#!/usr/bin/env bash
# Assembles dist/Rewarp.app from a release build. Signed ad hoc, for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

GHOSTTY_OPTIMIZE=ReleaseSafe scripts/build-ghostty-vt.sh
# SwiftPM does not track changes to the external static archive as target
# dependencies. A fresh package build also excludes artifacts from test builds.
rm -rf .build/package
swift build --scratch-path .build/package -c release --product Rewarp 2>&1 | tail -1

APP=dist/Rewarp.app
VERSION="$(scripts/version.sh)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/package/release/Rewarp "$APP/Contents/MacOS/Rewarp"
cp LICENSE "$APP/Contents/Resources/Rewarp-LICENSE.txt"
cp vendor/ghostty-src/LICENSE "$APP/Contents/Resources/Ghostty-LICENSE.txt"
cp vendor/ghostty-src/src/font/res/JetBrainsMonoNerdFont-Regular.ttf "$APP/Contents/Resources/"
cp vendor/ghostty-src/src/font/res/OFL.txt "$APP/Contents/Resources/JetBrainsMono-OFL.txt"
cp resources/icons/Rewarp.icns "$APP/Contents/Resources/Rewarp.icns"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp -R LICENSES "$APP/Contents/Resources/LICENSES"

cp -R resources/shell-integration "$APP/Contents/Resources/shell-integration"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Rewarp</string>
  <key>CFBundleDisplayName</key><string>Rewarp</string>
  <key>CFBundleIdentifier</key><string>dev.rewarp.Rewarp</string>
  <key>CFBundleExecutable</key><string>Rewarp</string>
  <key>CFBundleIconFile</key><string>Rewarp.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
