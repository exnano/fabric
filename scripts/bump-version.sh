#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/Config/Version.json"
PART="${1:-}"

if [[ "$PART" != "major" && "$PART" != "minor" && "$PART" != "patch" && "$PART" != "build" ]]; then
    print "Usage: $0 major|minor|patch|build" >&2
    exit 64
fi

VERSION="$(/usr/bin/plutil -extract marketingVersion raw "$VERSION_FILE")"
BUILD="$(/usr/bin/plutil -extract buildNumber raw "$VERSION_FILE")"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

case "$PART" in
    major)
        MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor)
        MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch)
        PATCH=$((PATCH + 1)) ;;
    build)
        ;;
esac

NEXT_VERSION="$MAJOR.$MINOR.$PATCH"
NEXT_BUILD=$((BUILD + 1))
/usr/bin/plutil -replace marketingVersion -string "$NEXT_VERSION" "$VERSION_FILE"
/usr/bin/plutil -replace buildNumber -integer "$NEXT_BUILD" "$VERSION_FILE"

print "Version is now $NEXT_VERSION ($NEXT_BUILD)."
print "Update CHANGELOG.md and README.md before creating a release commit/tag."
