#!/bin/sh
# Builds an arm64-only release binary and wraps it in build/Ripcord.app.
set -eu
cd "$(dirname "$0")/.."

# SWIFT_BUILD_FLAGS lets the Nix build pass --disable-sandbox; sandbox-exec is refused there.
# shellcheck disable=SC2086
swift build -c release --arch arm64 --product Ripcord ${SWIFT_BUILD_FLAGS:-}
# shellcheck disable=SC2086
bin="$(swift build -c release --arch arm64 --show-bin-path ${SWIFT_BUILD_FLAGS:-})"

app=build/Ripcord.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Ripcord" "$app/Contents/MacOS/Ripcord"
cp Resources/Info.plist "$app/Contents/Info.plist"

# sips renders the SVGs at each size, so the icons stay sharp without committed PNGs.
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -s format png -z $size $size Resources/AppIcon.svg --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -s format png -z $double $double Resources/AppIcon.svg --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
# 18pt tall, the menu bar's icon height.
sips -s format png -z 18 23 Resources/MenuBarIcon.svg --out "$app/Contents/Resources/MenuBarIcon.png" >/dev/null
sips -s format png -z 36 46 Resources/MenuBarIcon.svg --out "$app/Contents/Resources/MenuBarIcon@2x.png" >/dev/null
codesign --force --sign - "$app"
echo "$app"
