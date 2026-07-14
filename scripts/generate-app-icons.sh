#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT_DIR/Assets/AppIcon/FabricIcon.png"
OUTPUT_DIR="$ROOT_DIR/Assets/AppIcon/Generated"
ICONSET_DIR="$OUTPUT_DIR/FabricIcon.iconset"
LIGHT_ICON="$OUTPUT_DIR/FabricIcon-Light.png"
DARK_ICON="$OUTPUT_DIR/FabricIcon-Dark.png"

if ! command -v magick >/dev/null 2>&1; then
    print "ImageMagick is required to regenerate Fabric's app icons." >&2
    exit 69
fi

if [[ ! -f "$SOURCE" ]]; then
    print "Missing source icon: $SOURCE" >&2
    exit 66
fi

/bin/rm -rf "$ICONSET_DIR"
/bin/mkdir -p "$ICONSET_DIR"

function render_icon() {
    local background="$1"
    local destination="$2"

    # Clip the supplied transparent artwork to a macOS-style rounded backplate.
    # The large radius and inset keep corners clear at every generated icon size.
    magick \
        -size 1024x1024 xc:none \
        -fill "$background" \
        -draw "roundrectangle 48,48 976,976 210,210" \
        "$SOURCE" -compose over -composite \
        \( -size 1024x1024 xc:black -fill white \
           -draw "roundrectangle 48,48 976,976 210,210" \) \
        -alpha off -compose copy_opacity -composite \
        "$destination"
}

render_icon "#F1F4FC" "$LIGHT_ICON"
render_icon "#11131B" "$DARK_ICON"

for specification in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    size="${specification%% *}"
    filename="${specification#* }"
    magick "$LIGHT_ICON" -filter Lanczos -resize "${size}x${size}" "$ICONSET_DIR/$filename"
done

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_DIR/FabricIcon.icns"
/bin/rm -rf "$ICONSET_DIR"
print "Generated light, dark, and ICNS app icon resources in $OUTPUT_DIR"
