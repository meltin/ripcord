#!/bin/sh
# Makes a release's files in build/release: Ripcord-<version>.zip and appcast.xml, both to attach
# to the GitHub release v<version>. Needs the certificate from scripts/create-signing-certificate.sh
# and Sparkle's EdDSA key (generate_keys) in the keychain. Publishing is left to you; see
# CONTRIBUTING.md.
set -eu
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
sh scripts/build-app.sh >&2
app=build/Ripcord.app
# An ad hoc build would make every update drop the Accessibility grant.
if ! codesign -dvv "$app" 2>&1 | grep -qF 'Authority=Ripcord Self-Signed'; then
  echo "Not signed with \"Ripcord Self-Signed\"; run scripts/create-signing-certificate.sh." >&2
  exit 1
fi

out=build/release
rm -rf "$out"
mkdir -p "$out"
zip="$out/Ripcord-$version.zip"
ditto -c -k --keepParent "$app" "$zip"
# What's in the zip must still verify, or Sparkle refuses to install it.
check="$(mktemp -d)"
ditto -x -k "$zip" "$check"
codesign --verify --deep --strict "$check/Ripcord.app"
rm -rf "$check"

generate_appcast="$(find .build/artifacts -path '*/Sparkle/bin/generate_appcast' -type f | head -1)"
"$generate_appcast" \
  --download-url-prefix "https://github.com/meltin/ripcord/releases/download/v$version/" "$out"
echo "$out"
