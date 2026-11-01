#!/bin/zsh
# Builds Understage.app with only the Command Line Tools (no Xcode, no xcodegen).
# Usage: scripts/build-clt.sh [output dir]   default: .clt
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$root/.clt"}
app="$out/Understage.app"
version=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$root/project.yml")
build=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$root/project.yml")

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# 1. Compile. No Xcode means no SwiftUI macro plugin, so no @State/@Binding in sources.
cd "$root"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Sources App -name '*.swift' | sort)
swiftc -O -swift-version 6 -target arm64-apple-macos15.0 -parse-as-library \
  -module-name Understage "${sources[@]}" \
  -o "$app/Contents/MacOS/Understage"

# 2. Info.plist: App/Info.plist plus the keys Xcode would have generated.
cp App/Info.plist "$app/Contents/Info.plist"
pbuddy=/usr/libexec/PlistBuddy
set_key() {
  $pbuddy -c "Add :$1 $2 $3" "$app/Contents/Info.plist" 2>/dev/null ||
    $pbuddy -c "Set :$1 $3" "$app/Contents/Info.plist"
}
set_key CFBundleIdentifier string design.understage.app
set_key CFBundleName string Understage
set_key CFBundleDisplayName string Understage
set_key CFBundleExecutable string Understage
set_key CFBundlePackageType string APPL
set_key CFBundleInfoDictionaryVersion string 6.0
set_key CFBundleShortVersionString string "$version"
set_key CFBundleVersion string "$build"
set_key CFBundleIconFile string AppIcon
set_key CFBundleDevelopmentRegion string en
set_key LSMinimumSystemVersion string 15.0
set_key LSApplicationCategoryType string public.app-category.utilities
set_key LSUIElement bool true
set_key NSAppleEventsUsageDescription string 'Understage reads the current Finder folder and selected files so the command bar can act on them.'
set_key NSHighResolutionCapable bool true

# 3. Icon: actool ships with Xcode only, iconutil does not.
iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
for f in App/Assets.xcassets/AppIcon.appiconset/icon_*.png; do cp "$f" "$iconset/"; done
mv "$iconset/icon_1024.png" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "${iconset%/AppIcon.iconset}"

# 4. Resources ship as a folder, same as the Xcode resource phase.
cp -R Resources/Skills "$app/Contents/Resources/Skills"

# 5. Localization: xcstringstool ships with Xcode only, .strings files do not need it.
res="$app/Contents/Resources"
mkdir -p "$res/zh-Hans.lproj" "$res/en.lproj"
xcstrings_to_strings() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
src, dst, lang = sys.argv[1:4]
rows = json.load(open(src))["strings"]
def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
lines = []
for key, entry in rows.items():
    value = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {}).get("value")
    if value is not None:
        lines.append(f"{q(key)} = {q(value)};")
open(dst, "w").write("\n".join(lines) + "\n")
PY
}
xcstrings_to_strings App/Localizable.xcstrings "$res/zh-Hans.lproj/Localizable.strings" zh-Hans
xcstrings_to_strings App/InfoPlist.xcstrings "$res/zh-Hans.lproj/InfoPlist.strings" zh-Hans
xcstrings_to_strings App/InfoPlist.xcstrings "$res/en.lproj/InfoPlist.strings" en

# 6. Sign: hardened runtime + the AppleEvents entitlement TCC requires.
# A stable identity (scripts/make-dev-cert.sh) keeps TCC grants across rebuilds.
identity=${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null |
  sed -n 's/.*"\(Understage Dev\)".*/\1/p' | head -1)}
codesign --force --options runtime --entitlements App/Understage.entitlements \
  --sign "${identity:--}" "$app"
echo "$app"
