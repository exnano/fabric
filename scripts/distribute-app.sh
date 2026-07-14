#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Exnano Fabric.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
INSTALL_DIR="/Applications"
INSTALL_PATH="$INSTALL_DIR/$APP_NAME"
LEGACY_INSTALL_PATH="$HOME/Applications/$APP_NAME"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    print "DEVELOPER_ID_APPLICATION must contain a Developer ID Application identity." >&2
    exit 64
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    print "NOTARYTOOL_PROFILE must name credentials stored with 'xcrun notarytool store-credentials'." >&2
    exit 64
fi

TEMP_DIR="$(/usr/bin/mktemp -d -t exnano-fabric-release)"
ARCHIVE_PATH="$TEMP_DIR/Exnano-Fabric.zip"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT

# A clean release prevents renamed workspace paths and stale module caches from
# leaking into compiler artifacts.
/usr/bin/swift package --package-path "$ROOT_DIR" clean
"$ROOT_DIR/scripts/build-app.sh" release

# The development builder applies an ad-hoc signature. Replace it with a timestamped
# Developer ID signature and hardened runtime before submitting to Apple.
/usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ARCHIVE_PATH"

/usr/bin/xcrun notarytool submit "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

/usr/bin/xcrun stapler staple "$APP_DIR"
/usr/bin/xcrun stapler validate "$APP_DIR"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_DIR"

if [[ ! -w "$INSTALL_DIR" ]]; then
    print "Global Applications directory is not writable: $INSTALL_DIR" >&2
    print "Run from an administrator account or install the notarized bundle manually." >&2
    exit 77
fi

/bin/rm -rf "$INSTALL_PATH"
/usr/bin/ditto "$APP_DIR" "$INSTALL_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH"
/usr/bin/xcrun stapler validate "$INSTALL_PATH"

# Remove the old user-level copy only after the global installation validates.
if [[ -d "$LEGACY_INSTALL_PATH" ]]; then
    /bin/rm -rf "$LEGACY_INSTALL_PATH"
fi

print "Signed, notarized, stapled, and installed:"
print "$INSTALL_PATH"
