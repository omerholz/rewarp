#!/usr/bin/env bash
# Assembles dist/Rewarp.app from a release build. Signed ad hoc, for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-ghostty-vt.sh
swift build -c release --product Rewarp 2>&1 | tail -1

APP=dist/Rewarp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Rewarp "$APP/Contents/MacOS/Rewarp"
cp vendor/ghostty-src/src/font/res/JetBrainsMonoNerdFont-Regular.ttf "$APP/Contents/Resources/"
cp vendor/ghostty-src/src/font/res/OFL.txt "$APP/Contents/Resources/JetBrainsMono-OFL.txt"

cp -R resources/shell-integration "$APP/Contents/Resources/shell-integration"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Rewarp</string>
  <key>CFBundleDisplayName</key><string>Rewarp</string>
  <key>CFBundleIdentifier</key><string>dev.rewarp.Rewarp</string>
  <key>CFBundleExecutable</key><string>Rewarp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
