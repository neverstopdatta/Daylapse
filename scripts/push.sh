#!/bin/sh
# Commits everything that is not git-ignored and pushes the current branch.
#   scripts/push.sh "commit message" [-y]
# Shows what will be committed and asks first; -y skips the question.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

MESSAGE=""
YES=0
for arg in "$@"; do
    case "$arg" in
        -y) YES=1 ;;
        *) MESSAGE=$arg ;;
    esac
done
[ -n "$MESSAGE" ] || { echo 'usage: scripts/push.sh "commit message" [-y]' >&2; exit 2; }

if [ -z "$(git status --porcelain)" ]; then
    echo "Nothing to commit."
    exit 0
fi
git status --short
if [ "$YES" != 1 ]; then
    printf 'Commit all of this and push? [y/N] '
    read -r answer
    case "$answer" in y|Y) ;; *) echo "Cancelled."; exit 1 ;; esac
fi

BRANCH=$(git branch --show-current)
git add -A
git commit -m "$MESSAGE"
git push -u origin "$BRANCH"
