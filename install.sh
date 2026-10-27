#!/bin/bash
# Builds Pomodoro.app, puts it in ~/Applications, links the CLI to
# ~/.local/bin/pomodoro and starts it.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -x Pomodoro 2>/dev/null || true
mkdir -p ~/Applications ~/.local/bin
rm -rf ~/Applications/Pomodoro.app
cp -R build.noindex/Pomodoro.app ~/Applications/
ln -sf ~/Applications/Pomodoro.app/Contents/MacOS/Pomodoro ~/.local/bin/pomodoro
open ~/Applications/Pomodoro.app
echo "installed ~/Applications/Pomodoro.app and ~/.local/bin/pomodoro"
