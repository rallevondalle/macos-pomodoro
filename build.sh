#!/bin/bash
# Builds Pomodoro.app in build/ (ad-hoc signed, no Xcode project).
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Pomodoro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -target arm64-apple-macos15.0 \
  -o "$APP/Contents/MacOS/Pomodoro" Sources/*.swift
codesign --force --sign - "$APP"
echo "built $APP"
