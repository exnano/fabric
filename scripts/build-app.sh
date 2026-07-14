#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
VERSION_FILE="$ROOT_DIR/Config/Version.json"
APP_DIR="$ROOT_DIR/dist/Exnano Fabric.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

MARKETING_VERSION="$(/usr/bin/plutil -extract marketingVersion raw "$VERSION_FILE")"
BUILD_NUMBER="$(/usr/bin/plutil -extract buildNumber raw "$VERSION_FILE")"

cd "$ROOT_DIR"
/usr/bin/swift build --configuration "$CONFIGURATION"
BIN_DIR="$(/usr/bin/swift build --configuration "$CONFIGURATION" --show-bin-path)"

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
/bin/cp "$BIN_DIR/Fabric" "$MACOS_DIR/Fabric"
/bin/chmod 755 "$MACOS_DIR/Fabric"

/usr/bin/sed \
    -e "s/__MARKETING_VERSION__/$MARKETING_VERSION/g" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    "$ROOT_DIR/Config/Info.plist" > "$CONTENTS_DIR/Info.plist"

# Ad-hoc signing is appropriate for local development. Release distribution will
# replace this with Developer ID signing and notarization in a later phase.
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

print "Built $APP_DIR"
print "Version $MARKETING_VERSION ($BUILD_NUMBER)"
