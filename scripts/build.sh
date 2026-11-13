#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build -c release

APP="$ROOT/build/Screenshots Timelapse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/SSTL" "$APP/Contents/MacOS/SSTL"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/"

codesign --force --timestamp=none -s "SSTL Local Signing" -i dev.local.sstl "$APP"

# NO_LAUNCH=1 builds and signs only (used by release.sh).
[ "${NO_LAUNCH:-}" = 1 ] && exit 0

osascript -e 'tell application "Screenshots Timelapse" to quit' >/dev/null 2>&1 || true
open "$APP"
