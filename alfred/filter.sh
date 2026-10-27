#!/bin/bash
# Alfred Script Filter for `pomo <query>`: prints the matching actions as
# Alfred JSON, with the timer's status as the last row. Each item's arg is the CLI
# command run.sh runs; its msg variable is the notification text.
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh

q=$(printf '%s' "${1:-}" | /usr/bin/tr '[:upper:]' '[:lower:]')
read -r word rest <<< "$q" || true
word=${word:-}
rest=${rest:-}

items=""
esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }
add() { items="${items:+$items,}$1"; }
# item title subtitle arg msg: an action Enter runs.
item() {
  add "{\"title\":\"$(esc "$1")\",\"subtitle\":\"$(esc "$2")\",\"arg\":\"$(esc "$3")\",\"variables\":{\"msg\":\"$(esc "$4")\"}}"
}
# hint title subtitle autocomplete: a row that fills in the query instead.
hint() {
  add "{\"title\":\"$(esc "$1")\",\"subtitle\":\"$(esc "$2")\",\"valid\":false,\"autocomplete\":\"$(esc "$3")\"}"
}
info() { add "{\"title\":\"$(esc "$1")\",\"subtitle\":\"$(esc "$2")\",\"valid\":false}"; }
# Prints the items. No rerun: re-running every second makes Alfred jump the
# selection back to the top.
finish() { printf '{"items":[%s]}\n' "$items"; exit 0; }
# matches word alias…: the typed word is a prefix of one of the aliases.
matches() {
  local w=$1; shift
  for a in "$@"; do case $a in "$w"*) return 0 ;; esac; done
  return 1
}
# bare word alias…: the same, for actions that take nothing after the word.
bare() { [ -z "$rest" ] && matches "$@"; }

if [ -z "$BIN" ]; then
  item "Pomodoro er ikke installeret" "↩ åbner downloadsiden på GitHub" @install ""
  finish
fi
status=""
if /usr/bin/pgrep -qx Pomodoro; then status=$("$BIN" status 2>/dev/null || true); fi
if [ -z "$status" ]; then
  item "Pomodoro kører ikke" "↩ starter ${APP/#$HOME/~}" @open "Starter Pomodoro"
  finish
fi

read -r mode st phase round rem <<< "$status"
round=${round#r}
work=$(/usr/bin/defaults read com.rallevondalle.pomodoro workMinutes 2>/dev/null || echo 25)
short=$(/usr/bin/defaults read com.rallevondalle.pomodoro shortBreakMinutes 2>/dev/null || echo 5)
lunch=$(state lunchMinutes 45)
screen=$(state breakScreenMode deep)
case $mode in
  classic) modeLabel="Klassisk $work/$short" ;;
  deep) modeLabel="Dyb 50/10" ;;
  flow) modeLabel="Flow" ;;
  *) modeLabel=$mode ;;
esac
case $phase in
  short|manual) phaseLabel="Pause" ;;
  long) phaseLabel="Lang pause" ;;
  *) phaseLabel="Fokus" ;;
esac

# The status line, and the start/pause row worded like the panel's.
flowActive=false
if [ "$mode" = flow ] && [ "$st" != stopped ] && [ "$st" != ready ]; then flowActive=true; fi
case $st in
  stopped)
    statusTitle="Stoppet"; statusSub="$modeLabel"
    toggleTitle="Start fokus"; toggleMsg="Fokus startet" ;;
  ready)
    statusTitle="Pausen er slut"; statusSub="$modeLabel · klar til runde $round"
    toggleTitle="Start runde $round"; toggleMsg="Runde $round startet" ;;
  *)
    if $flowActive && [ "$phase" = work ]; then
      statusTitle="Fokus · $rem"; statusSub="Flow · tæller op"
    else
      statusTitle="$phaseLabel · $rem tilbage"; statusSub="$modeLabel · runde $round"
    fi
    [ "$st" = paused ] && statusTitle="$statusTitle (sat på pause)"
    if $flowActive; then
      if [ "$phase" = work ]; then toggleTitle="Tag pause"; toggleMsg="Pause startet"
      else toggleTitle="Tilbage til fokus"; toggleMsg="Tilbage til fokus"; fi
    elif [ "$st" = paused ]; then toggleTitle="Fortsæt"; toggleMsg="Fortsætter"
    else toggleTitle="Sæt på pause"; toggleMsg="Sat på pause"; fi ;;
esac
case $screen in
  deep) screenNow="kun i Dyb"; screenNext="alle pauser" ;;
  all) screenNow="i alle pauser"; screenNext="fra" ;;
  *) screenNow="fra"; screenNext="kun i Dyb" ;;
esac

focusItem() {
  case $1 in
    classic) item "Fokus: Klassisk $work/$short" "$work min fokus, $short min pause" "focus classic" "Klassisk fokus startet" ;;
    deep) item "Fokus: Dyb 50/10" "50 min fokus, 10 min pause · til krævende arbejde" "focus deep" "Dyb fokus startet" ;;
    flow) item "Fokus: Flow" "Tæller op · pausen bliver ⅕ af fokustiden" "focus flow" "Flow startet" ;;
  esac
}
breakItem() { item "Pause i $1 min" "Pause nu" "takeBreak $1" "Pause i $1 min"; }
# The minutes in $rest, or nothing: "25", "25m" and "25 min" all count.
minutes() {
  local n=${rest%% *}; n=${n%min}; n=${n%m}
  case $n in ''|*[!0-9]*) return 1 ;; esac
  [ "$n" -ge 1 ] && [ "$n" -le 240 ] && printf '%s' "$((10#$n))"
}

shown=0
if [ -z "$word" ] || bare "$word" start toggle resume fortsæt; then item "$toggleTitle" "$statusTitle · $statusSub" toggle "$toggleMsg"; shown=1; fi
if [ -n "$word" ] && matches "$word" break pause; then
  if n=$(minutes); then breakItem "$n"
  else for n in 5 10 15; do breakItem "$n"; done; fi
  shown=1
elif [ -z "$word" ]; then hint "Pause…" "5, 10, 15 min eller skriv selv: pomo break 25" "break "; fi
if [ -z "$word" ] || bare "$word" lunch frokost; then item "Frokost" "Pause i $lunch min" lunch "Frokost i $lunch min"; shown=1; fi
if [ -n "$word" ] && matches "$word" focus fokus; then
  picked=0
  for m in classic deep flow; do
    case $m in classic) a="classic klassisk" ;; deep) a="deep dyb" ;; flow) a="flow" ;; esac
    # shellcheck disable=SC2086
    if [ -z "$rest" ] || matches "$rest" $a; then focusItem $m; picked=1; fi
  done
  [ $picked = 1 ] || info "Ukendt fokus: $rest" "Brug classic/klassisk, deep/dyb eller flow"
  shown=1
elif [ -z "$word" ]; then hint "Fokus…" "Klassisk, Dyb eller Flow" "focus "
else
  # The mode names work on their own too: `pomo dyb`.
  matches "$word" classic klassisk && { focusItem classic; shown=1; }
  matches "$word" deep dyb && { focusItem deep; shown=1; }
  matches "$word" flow && { focusItem flow; shown=1; }
fi
if [ -z "$word" ] || bare "$word" skip spring next næste; then item "Spring over" "Videre til næste fase" skip "Sprunget over"; shown=1; fi
if [ -z "$word" ] || bare "$word" stop nulstil reset; then item "Stop" "Stop timeren og nulstil runderne" stop "Stoppet"; shown=1; fi
if [ -z "$word" ] || bare "$word" panel menu; then item "Panel" "Åbn eller luk panelet" panel ""; shown=1; fi
if [ -z "$word" ] || bare "$word" screen skærm; then
  item "Pauseskærm: $screenNow" "↩ skifter til $screenNext" cycleBreakScreen ""; shown=1
fi
[ $shown = 1 ] || info "Ingen handling for “$word”" "Prøv start, break 25, lunch, focus dyb, skip, stop, panel eller screen"
# The status goes last: Alfred selects the first row, and Enter on the status does nothing.
info "$statusTitle" "$statusSub"
finish
