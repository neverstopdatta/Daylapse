#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build -c release

APP="$ROOT/build/Daylapse.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/Daylapse" "$APP/Contents/MacOS/Daylapse"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

codesign --force --timestamp=none -s "Daylapse Local Signing" -i dev.local.daylapse "$APP"

osascript -e 'tell application "Daylapse" to quit' >/dev/null 2>&1 || true
open "$APP"
