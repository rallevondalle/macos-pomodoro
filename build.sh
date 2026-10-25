#!/bin/bash
# Builds Pomodoro.app in build/ as a universal binary (Apple silicon + Intel).
# Signs with the Developer ID Application identity in the keychain, with the
# hardened runtime (needed for notarization). Without one it signs ad hoc,
# which runs on this Mac only. SIGN_IDENTITY overrides the choice.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Pomodoro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos15.0 \
    -o build/obj/Pomodoro-$arch Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/Pomodoro" build/obj/Pomodoro-arm64 build/obj/Pomodoro-x86_64

identity=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}
if [ -n "$identity" ]; then
  codesign --force --options runtime --timestamp --sign "$identity" "$APP"
  echo "signed with $identity"
else
  codesign --force --sign - "$APP"
  echo "no Developer ID found: signed ad hoc (this Mac only)"
fi
codesign --verify --strict --verbose=1 "$APP"
echo "built $APP"
