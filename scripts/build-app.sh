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
# 18pt, the size of an icon in the panel's ⌘K menu.
sips -s format png -z 18 18 Resources/ThirdParty/GitHub.svg --out "$app/Contents/Resources/GitHub.png" >/dev/null
sips -s format png -z 36 36 Resources/ThirdParty/GitHub.svg --out "$app/Contents/Resources/GitHub@2x.png" >/dev/null
cp Resources/ThirdParty/GitHub-LICENSE.txt "$app/Contents/Resources/"
# Tabler Icons, drawn from their SVGs at any size.
cp -R Resources/Tabler "$app/Contents/Resources/"
cp Resources/ThirdParty/Tabler-LICENSE.txt "$app/Contents/Resources/"
# Search Emoji & Symbols' list, made by scripts/make-emoji-data.py.
cp -R Resources/Emoji "$app/Contents/Resources/"
cp Resources/ThirdParty/Unicode-LICENSE.txt "$app/Contents/Resources/"
# Sparkle, for updates in the app. ditto keeps the framework's symbolic links. Its XPC services
# are only for sandboxed apps, which Ripcord isn't.
framework="$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/Frameworks"
ditto "$bin/Sparkle.framework" "$framework"
rm -rf "$framework/XPCServices" "$framework/Versions/B/XPCServices"
cp Resources/ThirdParty/Sparkle-LICENSE.txt "$app/Contents/Resources/"
# Signed with the certificate from scripts/create-signing-certificate.sh when it's in the keychain,
# so macOS keeps permissions across builds; ad hoc otherwise (Nix, CI, a fresh clone).
# Sparkle's helpers and framework are signed first, inside out, with the same identity as the app.
identity="Ripcord Self-Signed"
sign() {
  for path in "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" \
    "$framework" "$app"; do
    codesign --force --sign "$1" "$path" || return 1
  done
}
if command -v security >/dev/null 2>&1 &&
  security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$identity\"" &&
  sign "$identity"; then
  echo "Signed with \"$identity\"." >&2
else
  # Also when the keychain is locked, as over SSH: a build beats none.
  echo "Signed ad hoc: no usable \"$identity\"; macOS will ask for Accessibility again." >&2
  sign -
fi
echo "$app"
