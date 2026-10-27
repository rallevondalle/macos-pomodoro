import AppKit
import Combine

// Port of BarWidget.qml. Menu bar face for the shared timer, and host for the
// dropdown panel.
// left = start/pause/resume · right = panel · middle = skip · scroll = ±1 min
final class StatusBarController: NSObject {
  let timer: TimerService
  let panel: PanelController
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var subs: Set<AnyCancellable> = []
  private var scrollMonitor: Any?
  private var scrollAccum: CGFloat = 0
  private let font: NSFont = {
    let size = NSFont.menuBarFont(ofSize: 0).pointSize
    return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
  }()

  init(timer: TimerService, panel: PanelController) {
    self.timer = timer
    self.panel = panel
    super.init()
    guard let button = item.button else { return }
    button.target = self
    button.action = #selector(clicked)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
    button.imagePosition = .imageLeading
    item.autosaveName = "pomodoro"

    panel.anchorRect = { [weak self] in self?.item.button?.window?.frame }

    // The menu bar item lives in its own window; catch the wheel over it.
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
      guard let self = self, e.window === self.item.button?.window else { return e }
      self.scrolled(e)
      return nil
    }

    timer.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.update() }
      .store(in: &subs)
    update()
  }

  @objc func clicked() {
    guard let e = NSApp.currentEvent else { return }
    // Go by the button number: menu bar managers like Bartender re-post
    // clicks, and a right click can arrive as an "other" mouse event.
    let right = e.type == .rightMouseUp || e.buttonNumber == 1
      || e.modifierFlags.contains(.control)
    let middle = !right && (e.type == .otherMouseUp || e.buttonNumber == 2)
    if right { panel.toggle() } else if middle { timer.skip() } else { timer.toggle() }
  }

  func scrolled(_ e: NSEvent) {
    let dy = e.scrollingDeltaY * (e.isDirectionInvertedFromDevice ? -1 : 1)
    // A wheel sends no gesture phase. Some mice (or their drivers) report each
    // notch as a precise delta of 1, so count every wheel event as one step and
    // only accumulate trackpad gestures.
    let wheel = !e.hasPreciseScrollingDeltas || (e.phase.isEmpty && e.momentumPhase.isEmpty)
    if wheel {
      if dy != 0 { timer.adjust(dy > 0 ? 1 : -1) }
      return
    }
    if e.phase == .began { scrollAccum = 0 }
    scrollAccum += dy
    if abs(scrollAccum) >= 24 {
      timer.adjust(scrollAccum > 0 ? 1 : -1)
      scrollAccum = 0
    }
  }

  private var lastTitle = ""
  private var lastSymbol = ""
  private var lastStyle = ""

  func update() {
    guard let button = item.button else { return }
    let t = timer
    let symbol = t.onBreak ? "cup.and.saucer" : "timer"
    let label: String
    if t.stopped { label = "" }
    else if t.ready { label = " start" }
    else { label = " " + (t.countingUp ? "↑" : "") + t.remainingText }
    let style = t.ready ? "active" : (t.stopped || t.paused ? "dimmed" : "normal")

    if symbol != lastSymbol {
      let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Pomodoro")
      img?.isTemplate = true
      button.image = img
      lastSymbol = symbol
    }
    if label != lastTitle {
      button.attributedTitle = NSAttributedString(string: label, attributes: [.font: font])
      lastTitle = label
    }
    if style != lastStyle {
      button.contentTintColor = style == "active" ? .controlAccentColor : nil
      button.appearsDisabled = style == "dimmed"
      lastStyle = style
    }
    button.toolTip = tooltip()
  }

  func tooltip() -> String {
    let t = timer
    let flow = t.mode == "flow" && !t.stopped && !t.ready
    let help = flow
      ? "\nVenstre: " + (t.phase == "work" ? "tag pause (\(t.flowBreakMinutes) min)" : "tilbage til fokus") + " · Højre: menu"
      : "\nVenstre: start/pause · Højre: menu · Midt: spring over · Scroll: ±1 min"
    if t.stopped { return "Pomodoro · " + t.modeLabel + " — klik for at starte" + help }
    if t.ready { return "Pausen er slut — klik for at starte runde \(t.round)" + help }
    return t.phaseLabel + " · " + t.modeLabel + " · runde \(t.round)"
      + (t.paused ? " (sat på pause)" : "") + " · " + t.remainingText + help
  }
}
