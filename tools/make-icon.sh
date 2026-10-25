#!/bin/bash
# Renders tools/icon.swift into AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
swiftc -O -swift-version 5 -o "$tmp/icon" tools/icon.swift
"$tmp/icon" "$tmp/icon-1024.png"
set=$tmp/AppIcon.iconset
mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/icon-1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$tmp/icon-1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o AppIcon.icns
cp "$tmp/icon-1024.png" docs/icon.png
rm -rf "$tmp"
echo "wrote AppIcon.icns and docs/icon.png"
