#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist .build
SMOKE_APP="$PWD/.build/Smoke Launcher.app"
SMOKE_LOG="$PWD/.build/smoke-launcher.log"
SMOKE_RESULT="$PWD/.build/smoke-result"
mkdir -p "$SMOKE_APP/Contents/MacOS"
cat > "$SMOKE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.hasensorbar.smoke-launcher</string>
<key>CFBundleExecutable</key><string>SmokeLauncher</string>
<key>CFBundleName</key><string>Smoke Launcher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swiftc -parse-as-library -warnings-as-errors scripts/SmokeLauncher.swift -o "$SMOKE_APP/Contents/MacOS/SmokeLauncher"
codesign --force --sign - "$SMOKE_APP"
rm -f "$SMOKE_RESULT"
: > "$SMOKE_LOG"
trap 'cat "$SMOKE_LOG"' EXIT
open -n -W "$SMOKE_APP" --args --root "$PWD" --log "$SMOKE_LOG" --result "$SMOKE_RESULT"
test -f "$SMOKE_RESULT"
test "$(cat "$SMOKE_RESULT")" = passed
