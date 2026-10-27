#!/bin/bash
# Runs the command picked in Alfred and prints a line for the notification.
# $1 is a CLI command ("takeBreak 25") or @open / @install; $msg comes from
# the result item and says what happened.
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh

case "${1:-}" in
  @install) /usr/bin/open "$RELEASES"; exit 0 ;;
  @open)
    if [ -n "$APP" ]; then /usr/bin/open "$APP"; echo "Starter Pomodoro"
    else /usr/bin/open "$RELEASES"; fi
    exit 0 ;;
esac

[ -n "${1:-}" ] || exit 0
[ -n "$BIN" ] || { echo "Pomodoro er ikke installeret"; exit 0; }
read -r -a args <<< "$1"
if ! out=$("$BIN" "${args[@]}" 2>&1); then
  echo "${out:-Pomodoro svarer ikke}"
  exit 0
fi
case "${args[0]}" in
  cycleBreakScreen)
    case "$out" in
      deep) echo "Pauseskærm: kun i Dyb" ;;
      all) echo "Pauseskærm: i alle pauser" ;;
      off) echo "Pauseskærm: fra" ;;
      *) echo "Pauseskærm: $out" ;;
    esac ;;
  *) out=${msg:-$out}; [ -z "$out" ] || echo "$out" ;;
esac
