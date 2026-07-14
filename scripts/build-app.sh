#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
VERSION_FILE="$ROOT_DIR/Config/Version.json"
APP_DIR="$ROOT_DIR/dist/Exnano Fabric.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_BUILD_DIR="$ROOT_DIR/.build/icon-assets"

MARKETING_VERSION="$(/usr/bin/plutil -extract marketingVersion raw "$VERSION_FILE")"
BUILD_NUMBER="$(/usr/bin/plutil -extract buildNumber raw "$VERSION_FILE")"

cd "$ROOT_DIR"
/usr/bin/swift build --configuration "$CONFIGURATION"
BIN_DIR="$(/usr/bin/swift build --configuration "$CONFIGURATION" --show-bin-path)"

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
/bin/cp "$BIN_DIR/Fabric" "$MACOS_DIR/Fabric"
/bin/chmod 755 "$MACOS_DIR/Fabric"

# SwiftPM can embed a build-machine Xcode toolchain rpath. System Swift libraries
# are sufficient for the deployment target, so remove local developer search paths.
while IFS= read -r rpath; do
    case "$rpath" in
        /Applications/Xcode.app/*|/Library/Developer/*)
            /usr/bin/install_name_tool -delete_rpath "$rpath" "$MACOS_DIR/Fabric"
            ;;
    esac
done < <(/usr/bin/otool -l "$MACOS_DIR/Fabric" | /usr/bin/awk \
    '/cmd LC_RPATH/ { getline; getline; print $2 }')
/bin/rm -rf "$ICON_BUILD_DIR"
/bin/mkdir -p "$ICON_BUILD_DIR"
/usr/bin/xcrun actool "$ROOT_DIR/Assets/AppIcon/ExnanoFabric.icon" \
    --compile "$ICON_BUILD_DIR" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 15.0 \
    --app-icon ExnanoFabric \
    --output-partial-info-plist "$ICON_BUILD_DIR/partial.plist"
/bin/cp "$ICON_BUILD_DIR/Assets.car" "$RESOURCES_DIR/Assets.car"
/bin/cp "$ICON_BUILD_DIR/ExnanoFabric.icns" "$RESOURCES_DIR/ExnanoFabric.icns"

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
