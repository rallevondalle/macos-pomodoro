#!/bin/bash
# Packs the Alfred workflow in alfred/ into build.noindex/Pomodoro.alfredworkflow,
# which is a plain zip. Double-click it to import it into Alfred 5.
set -euo pipefail
cd "$(dirname "$0")"
OUT=build.noindex/Pomodoro.alfredworkflow
plutil -lint -s alfred/info.plist
for f in alfred/*.sh; do bash -n "$f"; done
mkdir -p build
rm -f "$OUT"
(cd alfred && zip -q -X "../$OUT" info.plist icon.png filter.sh run.sh lib.sh)
echo "built $OUT"
