#!/bin/zsh
# Build products must already exist. Writes a DMG and a zip of Understage.app.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
derived=${1:-.derived}
version=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$root/project.yml")
app="$root/$derived/Build/Products/Release/Understage.app"
if [[ ! -d "$app" ]]; then
  echo "Missing $app. Run make dist first." >&2
  exit 1
fi
plist_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ "$plist_version" != "$version" ]]; then
  echo "App version $plist_version does not match project.yml $version." >&2
  exit 1
fi
out="$root/dist/release"
rm -rf "$out"
mkdir -p "$out"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/Understage.app"
ln -s /Applications "$stage/Applications"
dmg="$out/Understage-${version}-macOS-arm64.dmg"
zip="$out/Understage-${version}-macOS-arm64.zip"
hdiutil create -volname "Understage ${version}" -srcfolder "$stage" -ov -format UDZO "$dmg"
ditto -c -k --keepParent "$app" "$zip"
echo "$dmg"
echo "$zip"
