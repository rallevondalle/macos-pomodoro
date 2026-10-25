import AppKit
import Combine
import SwiftUI

// Port of BreakScreen.qml. Fullscreen break screen, one per display, shown
// during breaks when the timer asks for it (deep mode by default). It takes
// the keyboard and hides the Dock and menu bar so the break is a real break:
// L locks the Mac for leaving the desk, holding Esc for two seconds skips the
// break. When the break runs out the screen stays up and counts the overtime:
// Enter/Space starts the next focus, Esc does too with autoRestart (the
// default), otherwise it only closes it. The background fades from the theme
// to black over ten seconds; the overtime screen is always black.

final class BreakScreenState: ObservableObject {
  @Published var escProgress: Double = 0
  @Published var dim: Double = 0          // 0 = theme background, 1 = black
}

struct BreakView: View {
  @ObservedObject var timer: TimerService
  @ObservedObject var state: BreakScreenState
  let height: CGFloat

  var overtime: Bool { timer.overtime }
  var title: String {
    (overtime ? "Pausen er slut · over tiden" : timer.phaseLabel + " · " + timer.modeLabel).uppercased()
  }
  var escLabel: String {
    if !overtime { return "hold Esc  spring pausen over" }
    return timer.autoRestart ? "Esc  start runde \(timer.round)" : "Esc  luk pauseskærmen"
  }

  var body: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor).opacity(0.985)
      Color.black.opacity(state.dim)
      VStack(spacing: 18) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .tracking(4)
          .foregroundStyle(Color.accentColor)
        Text(overtime ? timer.overtimeText : timer.remainingText)
          .font(.system(size: min(220, height * 0.22), weight: .bold).monospacedDigit())
          .foregroundStyle(Color.primary)
        Text(overtime ? "Tag den tid du har brug for. Klar til runde \(timer.round)?" : timer.breakTip)
          .font(.system(size: 20))
          .multilineTextAlignment(.center)
          .foregroundStyle(Color.primary.opacity(0.8))
        Spacer().frame(height: 40)
        HStack(spacing: 48) {
          Text("L  lås skærmen").foregroundStyle(Color.secondary)
          if overtime && !timer.autoRestart {
            Text("Enter  start runde \(timer.round)").foregroundStyle(Color.accentColor)
          }
          Text(escLabel).foregroundStyle(state.escProgress > 0 ? Color.accentColor : Color.secondary)
        }
        .font(.system(size: 15))
        ZStack(alignment: .leading) {
          Capsule().fill(Color.primary.opacity(0.12))
          Capsule().fill(Color.accentColor).frame(width: 260 * state.escProgress)
        }
        .frame(width: 260, height: 3)
        .opacity(state.escProgress > 0 ? 1 : 0)
      }
      .frame(maxWidth: 900)
      .padding(.horizontal, 40)
    }
    .ignoresSafeArea()
  }
}

final class BreakWindow: NSWindow {
  var onKeyDown: ((NSEvent) -> Void)?
  var onKeyUp: ((NSEvent) -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func keyDown(with event: NSEvent) { onKeyDown?(event) }
  override func keyUp(with event: NSEvent) { onKeyUp?(event) }
  // Swallow ⌘-shortcuts (⌘Q, ⌘W, ⌘H) so they can't close the break.
  override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

final class BreakScreenController {
  let timer: TimerService
  let state = BreakScreenState()
  private var windows: [BreakWindow] = []
  private var subs: Set<AnyCancellable> = []
  private var escHeldSince: Date?
  private var escTimer: Timer?
  private var observers: [NSObjectProtocol] = []

  init(timer: TimerService) {
    self.timer = timer
    timer.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.sync() }
      .store(in: &subs)
    let nc = NotificationCenter.default
    observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                    object: nil, queue: .main) { [weak self] _ in self?.rebuild() })
    // Keep the keyboard: if something else takes focus, take it back.
    observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification,
                                    object: nil, queue: .main) { [weak self] _ in
      guard let self = self, !self.windows.isEmpty else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.grabFocus() }
    })
    sync()
  }

  var visible: Bool { !windows.isEmpty }

  func sync() {
    let want = timer.breakScreenActive
    if want && !visible { show() } else if !want && visible { hide() }
  }

  func show() {
    escHeldSince = nil
    state.escProgress = 0
    makeWindows()
    if timer.overtime {
      state.dim = 1
    } else {
      state.dim = 0
      DispatchQueue.main.async {
        withAnimation(.timingCurve(0.37, 0, 0.63, 1, duration: 10)) { self.state.dim = 1 }
      }
    }
    grabFocus()
  }

  func makeWindows() {
    closeWindows()
    for screen in NSScreen.screens {
      let w = BreakWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      w.setFrame(screen.frame, display: false)
      w.level = .screenSaver
      w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      w.isOpaque = false
      w.backgroundColor = .clear
      w.appearance = NSAppearance(named: .darkAqua)
      w.isReleasedWhenClosed = false
      w.contentView = NSHostingView(rootView: BreakView(timer: timer, state: state, height: screen.frame.height))
      w.onKeyDown = { [weak self] e in self?.keyDown(e) }
      w.onKeyUp = { [weak self] e in self?.keyUp(e) }
      w.orderFrontRegardless()
      windows.append(w)
    }
  }

  // Hiding the Dock and menu bar also posts a screen-parameters change; only
  // rebuild when a display was actually added, removed or resized.
  func rebuild() {
    guard visible else { return }
    let have = windows.map { NSStringFromRect($0.frame) }.sorted()
    let want = NSScreen.screens.map { NSStringFromRect($0.frame) }.sorted()
    if have == want { return }
    closeWindows()
    makeWindows()
    grabFocus()
  }

  func closeWindows() {
    windows.forEach { $0.orderOut(nil); $0.close() }
    windows.removeAll()
  }

  func grabFocus() {
    guard let first = windows.first else { return }
    NSApp.activate(ignoringOtherApps: true)
    try? setPresentation([.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication])
    first.makeKeyAndOrderFront(nil)
  }

  func setPresentation(_ options: NSApplication.PresentationOptions) throws {
    NSApp.presentationOptions = options
  }

  func hide() {
    escTimer?.invalidate()
    escTimer = nil
    escHeldSince = nil
    state.escProgress = 0
    NSApp.presentationOptions = []
    closeWindows()
    // Hand the focus back to whatever was in front before the break.
    NSApp.hide(nil)
  }

  func keyDown(_ e: NSEvent) {
    let overtime = timer.overtime
    switch e.keyCode {
    case 36, 76, 49:  // Return, Enter, Space
      if overtime && !e.isARepeat { timer.toggle() }
    case 53:  // Esc
      if e.isARepeat { return }
      if overtime { timer.dismissBreakScreen() } else { startEscHold() }
    case 37:  // L
      if !e.isARepeat { lockScreen() }
    default:
      break
    }
  }

  func keyUp(_ e: NSEvent) {
    if e.keyCode == 53 {
      escHeldSince = nil
      escTimer?.invalidate()
      escTimer = nil
      state.escProgress = 0
    }
  }

  func startEscHold() {
    escHeldSince = Date()
    escTimer?.invalidate()
    let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self = self, let since = self.escHeldSince else { return }
      self.state.escProgress = min(1, Date().timeIntervalSince(since) / 2)
      if self.state.escProgress >= 1 {
        self.escHeldSince = nil
        self.escTimer?.invalidate()
        self.escTimer = nil
        self.state.escProgress = 0
        self.timer.skip()
      }
    }
    RunLoop.main.add(t, forMode: .common)
    escTimer = t
  }

  // macOS has no public lock call; login.framework's SACLockScreenImmediate is
  // what the ⌃⌘Q menu item uses. Fall back to sleeping the display.
  func lockScreen() {
    typealias LockFn = @convention(c) () -> Int32
    let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
    if let handle = dlopen(path, RTLD_LAZY), let sym = dlsym(handle, "SACLockScreenImmediate") {
      _ = unsafeBitCast(sym, to: LockFn.self)()
      return
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["displaysleepnow"]
    try? p.run()
  }
}
