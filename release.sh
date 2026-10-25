#!/bin/bash
# Builds, signs and notarizes build/Pomodoro-<version>.dmg, ready to hand out.
# Needs a notarytool profile in the keychain (NOTARY_PROFILE, default
# cratedigger-notary, shared by my apps), made once with:
#   xcrun notarytool store-credentials cratedigger-notary \
#     --apple-id <apple id> --team-id XFQR9ZD5A3
# (it asks for an app-specific password from account.apple.com).
set -euo pipefail
cd "$(dirname "$0")"
PROFILE=${NOTARY_PROFILE:-cratedigger-notary}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG=build/Pomodoro-$VERSION.dmg

./build.sh
identity=$(codesign -dvv build/Pomodoro.app 2>&1 | sed -nE 's/^Authority=(Developer ID Application: .*)/\1/p' | head -1)
[ -n "$identity" ] || { echo "the app isn't signed with a Developer ID; can't notarize" >&2; exit 1; }

stage=build/dmg
rm -rf "$stage" "$DMG"
mkdir -p "$stage"
cp -R build/Pomodoro.app "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Pomodoro" -srcfolder "$stage" -fs HFS+ -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$identity" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
shasum -a 256 "$DMG"
echo "ready: $DMG"
