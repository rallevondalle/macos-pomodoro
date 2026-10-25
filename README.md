# <img src="docs/icon.png" width="64" align="center"> Pomodoro for macOS

![Pomodoro in the macOS menu bar](docs/hero.png)

A menu bar Pomodoro / focus timer for macOS, with breaks on demand, a
fullscreen break screen and defaults chosen from the research on work breaks.

It's a native port of [omarchy-pomodoro](https://github.com/rallevondalle/omarchy-pomodoro):
the same timer logic, modes, panel, break screen and Danish texts. The reasoning
behind the defaults is in that README. Ported from omarchy-pomodoro
[`987c979`](https://github.com/rallevondalle/omarchy-pomodoro/commit/987c979);
diff from there to see what hasn't been carried over yet.

> The interface is in Danish (Fokus = focus, Pause = break, Frokost = lunch).

## Install

```bash
./install.sh     # builds, copies to ~/Applications, links ~/.local/bin/pomodoro, starts it
```

Needs Xcode's Swift toolchain, no Xcode project. "Start ved login" is in the panel's settings.

If the menu bar is full, macOS hides the timer without a word. Make room
(⌘-drag other icons off, or turn things off under System Settings → Menu Bar).
A menu bar manager like Bartender may put it under "Always Hidden" at first;
move it to "Shown" once and it stays there. `pomodoro panel` opens the panel
top right even when the icon is hidden.

## Build and release

- `./build.sh` builds a universal app (Apple silicon + Intel) in `build/`. It signs
  with the Developer ID Application identity in the keychain and the hardened
  runtime, or ad hoc when there is none.
- `./release.sh` also packs `build/Pomodoro-<version>.dmg`, notarizes it with
  the notarytool profile in `NOTARY_PROFILE` (default `cratedigger-notary`), staples the ticket and checks it
  with Gatekeeper.
- `tools/make-icon.sh` redraws `AppIcon.icns` from `tools/icon.swift`.

## Use

| In the menu bar | Action |
| --- | --- |
| Left click | Start / pause / resume (flow: focus ⇄ break) |
| Right click (or ⌃-click) | Open the panel |
| Middle click | Skip to the next phase |
| Scroll | ±1 minute on the running countdown |

The panel works as in Omarchy: `1`–`9`, `0` for the actions, arrows / `j` `k` + Enter,
`s` for settings, Esc back/close. Added on the Mac: `q` Afslut, and "Start ved login" in settings.

![Break screen](docs/breakscreen.png)

**Break screen**: covers every display at screen-saver level, hides the Dock and
menu bar and blocks ⌘-Tab while it's up. `L` locks the Mac, hold `Esc` for two
seconds to skip, and after the break it counts the overtime on black until
Enter/Space (or Esc with "start fokus ved luk" on).

Classic lengths:

```bash
defaults write com.rallevondalle.pomodoro workMinutes -int 30
# also: shortBreakMinutes, longBreakMinutes, roundsPerLongBreak
```

CLI (the app binary, linked as `pomodoro`):

```bash
pomodoro panel                 # open/close the panel (bind it in Raycast/Shortcuts)
pomodoro toggle | skip | stop | status | mode
pomodoro focus deep            # classic | deep | flow
pomodoro takeBreak 10
pomodoro lunch
pomodoro cycleBreakScreen      # deep → all → off
pomodoro toggleAutoRestart | dismissBreakScreen | setMode flow
```

State lives in `~/Library/Application Support/Pomodoro/state.json` (same fields as the
Omarchy version), deadline-based, so sleep and relaunches don't skew it.

## Differences from Omarchy, forced by macOS

- Icons are SF Symbols instead of Nerd Font glyphs.
- The theme colours are macOS's: the break screen is always dark, the accent is the system accent.
- The break screen can't take the keyboard exclusively like a Wayland overlay; it
  hides Dock/menu bar, blocks app switching and takes focus back if it loses it.
- Lock uses the same call as  → Lock Screen (⌃⌘Q).

## License

MIT
