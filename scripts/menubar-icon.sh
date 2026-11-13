#!/bin/sh
# Turns an SVG into the menu bar icon and applies it.
#   scripts/menubar-icon.sh [icon.svg] [--no-build]
# Design on an 18x18 canvas with the artwork inside 16x16, drawn in black on a transparent background:
# the app loads it as a template image, so macOS recolours it for light, dark and highlighted states.
# Writes Resources/MenuBarIcon.svg, MenuBarIcon.png (18 px) and MenuBarIcon@2x.png (36 px), then rebuilds and relaunches.
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
SVG=${SVG:-$ROOT/Resources/MenuBarIcon.svg}
[ -f "$SVG" ] || { echo "SVG not found: $SVG" >&2; exit 1; }

render_svg "$SVG" "$ROOT/Resources/MenuBarIcon.png" 18 18
render_svg "$SVG" "$ROOT/Resources/MenuBarIcon@2x.png" 36 36
[ "$SVG" -ef "$ROOT/Resources/MenuBarIcon.svg" ] || cp "$SVG" "$ROOT/Resources/MenuBarIcon.svg"
echo "Menu bar icon updated from $SVG"

[ "$BUILD" = 1 ] && sh "$ROOT/scripts/build.sh"
exit 0
