#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="XArticleReader"
BUILD_DIR="$ROOT/.build/arm64-apple-macosx/debug"
EXECUTABLE="$BUILD_DIR/$APP_NAME"
BUNDLE_DIR="$ROOT/.build/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Expected built executable at $EXECUTABLE" >&2
  echo "Run: swift build" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"

cat >"$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>XArticleReader</string>
  <key>CFBundleIdentifier</key>
  <string>com.miningstore.xarticlereader</string>
  <key>CFBundleName</key>
  <string>XArticleReader</string>
  <key>CFBundleDisplayName</key>
  <string>XArticleReader</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

ln -sf "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

echo "$BUNDLE_DIR"
