#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
APP="dist/HA Sensor Bar.app"
test "$(lipo -archs "$APP/Contents/MacOS/HASensorBarApp")" = "arm64"
test "$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")" = "14.0"
test "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")" = "true"
test "$(plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw "$APP/Contents/Info.plist")" = "true"
test -s "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/ha-sensor-bar-mount.XXXXXX")"
UNZIP="$(mktemp -d "${TMPDIR:-/tmp}/ha-sensor-bar-unzip.XXXXXX")"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" = 1 ]]; then hdiutil detach "$MOUNT"; fi
    rm -rf "$MOUNT" "$UNZIP"
}
trap cleanup EXIT
hdiutil attach "dist/HA-Sensor-Bar-$VERSION-arm64.dmg" -mountpoint "$MOUNT" -nobrowse -readonly
MOUNTED=1
test -d "$MOUNT/HA Sensor Bar.app"
test -L "$MOUNT/Applications"
test "$(readlink "$MOUNT/Applications")" = "/Applications"
codesign --verify --deep --strict "$MOUNT/HA Sensor Bar.app"
hdiutil detach "$MOUNT"
MOUNTED=0
ditto -x -k "dist/HA-Sensor-Bar-$VERSION-arm64.zip" "$UNZIP"
codesign --verify --deep --strict "$UNZIP/HA Sensor Bar.app"
test "$(lipo -archs "$UNZIP/HA Sensor Bar.app/Contents/MacOS/HASensorBarApp")" = "arm64"
(cd dist && shasum -a 256 -c SHA256SUMS.txt)
echo "Verified arm64, bundle metadata, signatures, DMG contents, ZIP, and checksums."
