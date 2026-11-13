#!/bin/sh
# Turns an SVG into the app icon and applies it.
#   scripts/app-icon.sh [icon.svg] [--no-build]
# Design on a 1024x1024 canvas with the shape about 824 px wide (about 100 px transparent margin), like Apple's
# macOS icon template. macOS does not round the corners for you, so draw the squircle in the SVG.
# Writes Resources/AppIcon.svg, AppIcon-1024.png and AppIcon.icns, then rebuilds and relaunches the app.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/_render.sh"

SVG=""
BUILD=1
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) SVG=$arg ;;
    esac
done
SVG=${SVG:-$ROOT/Resources/AppIcon.svg}
[ -f "$SVG" ] || { echo "SVG not found: $SVG" >&2; exit 1; }

SET=$(mktemp -d)/AppIcon.iconset
trap 'rm -rf "$(dirname "$SET")"' EXIT
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    render_svg "$SVG" "$SET/icon_${size}x${size}.png" "$size" "$size"
    render_svg "$SVG" "$SET/icon_${size}x${size}@2x.png" $((size * 2)) $((size * 2))
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
render_svg "$SVG" "$ROOT/Resources/AppIcon-1024.png" 1024 1024
[ "$SVG" -ef "$ROOT/Resources/AppIcon.svg" ] || cp "$SVG" "$ROOT/Resources/AppIcon.svg"
echo "App icon updated from $SVG"

[ "$BUILD" = 1 ] && sh "$ROOT/scripts/build.sh"
exit 0
