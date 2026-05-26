#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/Codex Config Importer.app"
EXECUTABLE="$APP/Contents/MacOS/CodexConfigImporter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/ConfigImporterInfo.plist" "$APP/Contents/Info.plist"
cp "$ROOT/config-importer.mjs" "$APP/Contents/Resources/config-importer.mjs"
cp "$ROOT/README.md" "$APP/Contents/Resources/README.md"

chmod +x "$APP/Contents/Resources/config-importer.mjs"
xcrun swiftc \
  -O \
  -framework AppKit \
  "$ROOT/CodexPlusUI.swift" \
  -o "$EXECUTABLE"
chmod +x "$EXECUTABLE"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "$APP"
