#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build -c release

APP="$ROOT/build/Screenshots Timelapse.app"
rm -rf "$ROOT/build/Daylapse.app" "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Daylapse" "$APP/Contents/MacOS/Daylapse"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/"

codesign --force --timestamp=none -s "Daylapse Local Signing" -i dev.local.daylapse "$APP"

osascript -e 'tell application "Screenshots Timelapse" to quit' >/dev/null 2>&1 || true
open "$APP"
