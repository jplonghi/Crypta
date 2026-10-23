#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' CryptaApp/Resources/Info.plist)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a MAJOR.MINOR.PATCH app version, got: $version" >&2
    exit 1
fi
if [[ -n "${1:-}" && "$1" != "v$version" ]]; then
    echo "Tag $1 does not match app version v$version" >&2
    exit 1
fi

xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/release/DerivedData \
    -onlyUsePackageVersionsFromResolvedFile build

app="$PWD/build/release/DerivedData/Build/Products/Release/Crypta.app"
test "$(lipo -archs "$app/Contents/MacOS/Crypta")" = arm64
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version"

# Keep licenses inside the app so both distribution formats retain them.
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --sign - --options runtime \
    --entitlements CryptaApp/Resources/Crypta.entitlements "$app"
codesign --verify --deep --strict "$app"

mkdir -p dist
stage=$(mktemp -d "$PWD/build/release/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Crypta.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/How to install.txt" <<'NOTES'
Crypta for Apple Silicon — macOS 14 or later

1. Drag Crypta.app onto the Applications folder shortcut.
2. Eject this disk image.
3. Open Crypta from Applications.

Updating? Quit Crypta first, then replace the existing app.
Keep a backup of your vault. This personal POC uses one current file
structure; development updates may require recreating older test vaults.

Crypta has not had an independent security audit. Use synthetic data
while evaluating it. This build is ad-hoc signed and not notarized.
If macOS blocks the first launch and you trust this download, try opening
the installed app, then use System Settings > Privacy & Security > Open Anyway.
https://support.apple.com/en-us/102445

https://github.com/jplonghi/Crypta
NOTES

# Package the verified app; never reuse an archive from an earlier build.
rm -f dist/Crypta-macOS-arm64.zip
ditto -c -k --sequesterRsrc --keepParent "$app" dist/Crypta-macOS-arm64.zip
hdiutil create -volname Crypta -srcfolder "$stage" -format UDZO -fs HFS+ \
    -ov "$PWD/dist/Crypta-macOS-arm64.dmg"
hdiutil verify dist/Crypta-macOS-arm64.dmg
(cd dist && shasum -a 256 Crypta-macOS-arm64.dmg Crypta-macOS-arm64.zip > SHA256SUMS.txt)
echo "Packaged Crypta $version in dist/ (ad-hoc signed, not notarized)."
