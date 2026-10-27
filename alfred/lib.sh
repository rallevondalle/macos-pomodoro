# Shared by filter.sh and run.sh: finds the app and its state.
# Alfred runs scripts without the user's PATH, so everything is absolute.

RELEASES=https://github.com/rallevondalle/macos-pomodoro/releases/latest
STATE="$HOME/Library/Application Support/Pomodoro/state.json"

# The app bundle: /Applications first, then ~/Applications.
APP=""
for a in /Applications/Pomodoro.app "$HOME/Applications/Pomodoro.app"; do
  if [ -x "$a/Contents/MacOS/Pomodoro" ]; then APP=$a; break; fi
done
BIN=${APP:+$APP/Contents/MacOS/Pomodoro}

# One value from state.json, or $2 when it isn't there.
state() {
  /usr/bin/plutil -extract "$1" raw -o - "$STATE" 2>/dev/null || printf '%s' "$2"
}
