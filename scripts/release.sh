#!/bin/sh
# Builds the app and publishes it as a GitHub release.
#   scripts/release.sh <version> [--notes "text"] [--dry-run]
# Example: scripts/release.sh 1.1
#
# What it does: sets the version in Info.plist, builds, zips the app as Screenshots-Timelapse.zip, commits the
# version bump, tags v<version>, pushes, and creates the release with the zip attached.
#
# It never changes an existing release. If v<version> already exists as a tag or release it stops: to ship a fix,
# release a higher version. A version lower than the newest existing tag is published without the "Latest" badge,
# so the in-app update check (which reads GitHub's latest release) keeps pointing at the newest version.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION=""
NOTES=""
DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --notes) NOTES=${2:?--notes needs text}; shift ;;
        --dry-run) DRY=1 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) VERSION=${1#v} ;;
    esac
    shift
done
echo "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$' || { echo 'usage: scripts/release.sh <version, like 1.1 or 1.1.2> [--notes "text"] [--dry-run]' >&2; exit 2; }
TAG="v$VERSION"

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login" >&2; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "Release from the main branch." >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first (scripts/push.sh does both steps)." >&2; exit 1; }
git fetch --tags --quiet
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || gh release view "$TAG" >/dev/null 2>&1; then
    echo "$TAG already exists. Existing releases are never overwritten; release a higher version instead." >&2
    exit 1
fi

NEWEST=$( (git tag -l 'v*' | sed 's/^v//'; echo "$VERSION") | sort -V | tail -1)
LATEST_FLAG=""
if [ "$NEWEST" != "$VERSION" ]; then
    LATEST_FLAG="--latest=false"
    echo "Note: v$NEWEST already exists and is newer, so $TAG will not be marked as the latest release."
fi

APP="$ROOT/build/Screenshots Timelapse.app"
ZIP="$ROOT/build/Screenshots-Timelapse.zip"

if [ "$DRY" = 1 ]; then
    echo "Dry run. Would:"
    echo "  set CFBundleShortVersionString to $VERSION in Info.plist and commit it"
    echo "  build $APP and zip it to $ZIP"
    echo "  tag $TAG, push main and the tag"
    echo "  gh release create $TAG $ZIP $LATEST_FLAG"
    exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
NO_LAUNCH=1 sh scripts/build.sh
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

git add Info.plist
git diff --cached --quiet || git commit -m "Release $TAG"
git tag -a "$TAG" -m "Screenshots Timelapse $VERSION"
git push origin main "$TAG"

if [ -n "$NOTES" ]; then
    gh release create "$TAG" "$ZIP" --title "Screenshots Timelapse $VERSION" --notes "$NOTES" $LATEST_FLAG
else
    gh release create "$TAG" "$ZIP" --title "Screenshots Timelapse $VERSION" --generate-notes $LATEST_FLAG
fi
