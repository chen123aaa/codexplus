#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/CodexPlus.app"
OLD_APP="/Applications/Codex 插件解锁.app"

rm -rf "$APP"
rm -rf "$OLD_APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/CodexPlus" "$APP/Contents/MacOS/CodexPlus"
cp "$ROOT/unlocker.mjs" "$APP/Contents/Resources/unlocker.mjs"
cp "$ROOT/README.md" "$APP/Contents/Resources/README.md"

chmod +x "$APP/Contents/MacOS/CodexPlus"
chmod +x "$APP/Contents/Resources/unlocker.mjs"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "$APP"
