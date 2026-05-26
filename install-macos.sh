#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/CodexPlus.app"
OLD_APP="/Applications/Codex 插件解锁.app"
EXECUTABLE="$APP/Contents/MacOS/CodexPlus"

rm -rf "$APP"
rm -rf "$OLD_APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/unlocker.mjs" "$APP/Contents/Resources/unlocker.mjs"
cp "$ROOT/README.md" "$APP/Contents/Resources/README.md"

chmod +x "$APP/Contents/Resources/unlocker.mjs"
xcrun swiftc \
  -O \
  -framework AppKit \
  "$ROOT/CodexPlusUI.swift" \
  -o "$EXECUTABLE"
chmod +x "$EXECUTABLE"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "$APP"
