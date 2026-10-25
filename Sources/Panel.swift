import AppKit
import Combine
import ServiceManagement
import SwiftUI

// Port of Panel.qml. Dropdown under the menu bar timer: status header plus up
// to ten actions on the number keys (1–9, 0), and a settings view (s) for the
// lunch length and which actions are shown. Arrows/jk + Enter also work; Esc
// goes back/closes.

let donateURL = URL(string: "https://donate.stripe.com/6oUdR8cAq7Qs9cu3YFgA806")!

struct PanelRow {
  var kind: String
  var id = ""
  var group: String
  var key = ""
  var icon = ""
  var label: String
  var menuLabel = ""
  var hint = ""
  var info = ""
  var mode = ""
  var needsActive = false
  var current = false
  var disabled = false
  var dim = false
  var run: (() -> Void)? = nil
}

final class PanelModel: ObservableObject {
  let timer: TimerService
  @Published var selected = 0
  @Published var settingsView = false
  var close: () -> Void = {}
  private var scrollAccum: CGFloat = 0

  init(timer: TimerService) { self.timer = timer }

  var flowActive: Bool { timer.mode == "flow" && !timer.stopped && !timer.ready }
  var toggleLabel: String {
    if timer.stopped { return "Start fokus" }
    if timer.ready { return "Start runde \(timer.round)" }
    if flowActive { return timer.phase == "work" ? "Tag pause · \(timer.flowBreakMinutes) min" : "Tilbage til fokus" }
    return timer.paused ? "Fortsæt" : "Sæt på pause"
  }
  var toggleIcon: String {
    if flowActive { return timer.phase == "work" ? "cup.and.saucer" : "timer" }
    return timer.stopped || timer.ready || timer.paused ? "play.fill" : "pause.fill"
  }
  var lunchMinutes: Int { timer.lunchMinutes }
  var hiddenItems: [String] { timer.hiddenItems }

  var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }

  // Every action the panel knows. `key` is its fixed number in the settings
  // view; the main view numbers the visible ones 1..9, 0 in order.
  var allActions: [PanelRow] {
    let t = timer
    return [
      PanelRow(kind: "action", id: "toggle", group: "", icon: toggleIcon, label: toggleLabel,
               menuLabel: "Start / pause", run: { t.toggle() }),
      PanelRow(kind: "action", id: "classic", group: "Fokus", icon: "timer",
               label: "Klassisk " + t.fmt(t.config.work) + "/" + t.fmt(t.config.shortBreak),
               hint: "standard", mode: "classic", run: { t.startFocus("classic") }),
      PanelRow(kind: "action", id: "deep", group: "Fokus", icon: "timer", label: "Dyb 50/10",
               hint: "krævende", mode: "deep", run: { t.startFocus("deep") }),
      PanelRow(kind: "action", id: "flow", group: "Fokus", icon: "timer", label: "Flow",
               hint: "pause = ⅕ af fokus", mode: "flow", run: { t.startFocus("flow") }),
      PanelRow(kind: "action", id: "b5", group: "Pause", icon: "cup.and.saucer", label: "5 min",
               hint: "mikropause", run: { t.takeBreak(5) }),
      PanelRow(kind: "action", id: "b10", group: "Pause", icon: "cup.and.saucer", label: "10 min",
               run: { t.takeBreak(10) }),
      PanelRow(kind: "action", id: "b15", group: "Pause", icon: "cup.and.saucer", label: "15 min",
               hint: "lang pause", run: { t.takeBreak(15) }),
      PanelRow(kind: "action", id: "lunch", group: "Pause", icon: "fork.knife", label: "Frokost",
               hint: "\(lunchMinutes) min", run: { t.takeBreak(Double(t.lunchMinutes)) }),
      PanelRow(kind: "action", id: "skip", group: "-", icon: "forward.end.fill", label: "Spring over",
               hint: "næste fase", needsActive: true, run: { t.skip() }),
      PanelRow(kind: "action", id: "stop", group: "-", icon: "stop.fill", label: "Stop",
               hint: "nulstil", needsActive: true, run: { t.stop() })
    ]
  }

  let info: [String: String] = [
    "toggle": "Starter, pauser eller fortsætter den aktuelle fase. I Flow skifter den mellem fokus og pause. Samme som venstreklik på timeren.",
    "classic": "25 min fokus og 5 min pause. Efter 4 runder en lang pause på 15 min. Passer til de fleste opgaver.",
    "deep": "50 min fokus og 10 min pause, 30 min pause efter 2 runder. Til krævende arbejde, hvor 25 min er for kort.",
    "flow": "Tæller op. Arbejd, til fokus slipper, og klik så på timeren for pause. Pausen bliver ⅕ af fokustiden, 2–30 min.",
    "b5": "Kort pause nu: rejs dig, kig langt væk og drik vand. Telefonen genoplader dårligt.",
    "b10": "Pause nu. En afbrudt fokusrunde tæller ikke med mod den lange pause.",
    "b15": "Lang pause nu. Længere pauser hjælper mere efter krævende arbejde.",
    "lunch": "Frokostpause. Længden ændres under Indstillinger.",
    "skip": "Afslut den aktuelle fase: fra fokus til pause, eller fra pause til fokus.",
    "stop": "Stop timeren og nulstil runderne.",
    "settings": "Frokostlængde, pauseskærm og hvilke punkter der vises i menuen.",
    "lunchLength": "Længden på frokostpausen. Brug ← → eller klik på pilene.",
    "breakscreen": "Fuldskærm med nedtælling i pauserne: kun i Dyb, i alle pauser eller fra. L låser, hold Esc springer over.",
    "autorestart": "Når pausen er slut, tæller pauseskærmen op. Til: Esc starter næste fokus. Fra: Esc lukker bare skærmen.",
    "login": "Start Pomodoro automatisk, når du logger ind på Mac'en.",
    "visibility": "Vis eller skjul punktet i menuen. Synlige punkter nummereres 1–9, 0.",
    "back": "Tilbage til menuen.",
    "donate": "Pomodoro er gratis. Hjælper den dig, kan du støtte den med et bidrag. Åbner donationssiden i browseren.",
    "quit": "Luk Pomodoro. Timeren fortsætter, hvor den var, når du åbner den igen."
  ]

  func keyFor(_ i: Int) -> String { String((i + 1) % 10) }

  var rows: [PanelRow] {
    var list: [PanelRow] = []
    if settingsView {
      list.append(PanelRow(kind: "lunch", group: "Frokostpause", icon: "fork.knife", label: "Længde",
                           hint: "‹  \(lunchMinutes) min  ›", info: info["lunchLength"]!))
      let screenMode = timer.breakScreenMode
      list.append(PanelRow(kind: "breakscreen", group: "Pauseskærm",
                           icon: screenMode == "off" ? "square" : "checkmark.square.fill",
                           label: "Vis i pauser",
                           hint: "‹  " + (["deep": "kun dyb", "all": "alle", "off": "fra"][screenMode] ?? "") + "  ›",
                           info: info["breakscreen"]!, dim: screenMode == "off"))
      let restart = timer.autoRestart
      list.append(PanelRow(kind: "autorestart", group: "Pauseskærm",
                           icon: restart ? "checkmark.square.fill" : "square",
                           label: "Start fokus ved luk", hint: "‹  " + (restart ? "til" : "fra") + "  ›",
                           info: info["autorestart"]!, dim: !restart))
      let login = loginEnabled
      list.append(PanelRow(kind: "login", group: "Mac", icon: login ? "checkmark.square.fill" : "square",
                           label: "Start ved login", hint: "‹  " + (login ? "til" : "fra") + "  ›",
                           info: info["login"]!, dim: !login))
      for (i, a) in allActions.enumerated() {
        let shown = !hiddenItems.contains(a.id)
        list.append(PanelRow(kind: "visibility", id: a.id, group: "Vis i menuen", key: keyFor(i),
                             icon: shown ? "checkmark.square.fill" : "square",
                             label: a.menuLabel.isEmpty ? a.label : a.menuLabel,
                             hint: a.group == "-" ? "" : a.group.lowercased(),
                             info: info["visibility"]!, dim: !shown))
      }
      list.append(PanelRow(kind: "back", group: "-", key: "esc", icon: "arrow.left", label: "Tilbage",
                           info: info["back"]!))
      return list
    }
    var n = 0
    for b in allActions {
      if hiddenItems.contains(b.id) { continue }
      var r = b
      r.key = keyFor(n)
      n += 1
      r.info = info[b.id] ?? ""
      r.current = !b.mode.isEmpty && timer.mode == b.mode
      r.disabled = b.needsActive && timer.stopped
      list.append(r)
    }
    list.append(PanelRow(kind: "settings", group: "-settings", key: "s", icon: "gearshape",
                         label: "Indstillinger", info: info["settings"]!))
    list.append(PanelRow(kind: "donate", group: "-settings", key: "d", icon: "heart",
                         label: "Støt Pomodoro", hint: "fra 5 €", info: info["donate"]!))
    list.append(PanelRow(kind: "quit", group: "-settings", key: "q", icon: "power",
                         label: "Afslut", info: info["quit"]!))
    return list
  }

  func enabledAt(_ i: Int, _ rows: [PanelRow]) -> Bool {
    i >= 0 && i < rows.count && !rows[i].disabled
  }

  func activate(_ i: Int) {
    let rows = self.rows
    guard enabledAt(i, rows) else { return }
    let row = rows[i]
    switch row.kind {
    case "action": row.run?(); close()
    case "settings": showSettings(true)
    case "back": showSettings(false)
    case "visibility": timer.toggleHidden(row.id)
    case "breakscreen": timer.cycleBreakScreen(1)
    case "autorestart": timer.toggleAutoRestart()
    case "login": toggleLogin()
    case "lunch": timer.setLunchMinutes(lunchMinutes + 5)
    case "donate": NSWorkspace.shared.open(donateURL); close()
    case "quit": NSApp.terminate(nil)
    default: break
    }
  }

  // Lunch length, break-screen mode, auto-restart and login are steppers: ← / → move them.
  func step(_ row: PanelRow, _ delta: Int) {
    switch row.kind {
    case "lunch": adjustLunch(delta)
    case "breakscreen": timer.cycleBreakScreen(delta)
    case "autorestart": timer.toggleAutoRestart()
    case "login": toggleLogin()
    default: break
    }
  }

  func isStepper(_ row: PanelRow) -> Bool {
    ["lunch", "breakscreen", "autorestart", "login"].contains(row.kind)
  }

  func adjustLunch(_ delta: Int) { timer.setLunchMinutes(lunchMinutes + delta * 5) }

  func toggleLogin() {
    do {
      if loginEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
    } catch {
      NSLog("pomodoro: login-punkt fejlede: \(error)")
    }
    objectWillChange.send()
  }

  func showSettings(_ value: Bool) {
    settingsView = value
    selected = 0
  }

  func move(_ delta: Int) {
    let rows = self.rows
    let n = rows.count
    var i = selected
    repeat { i = ((i + delta) % n + n) % n } while !enabledAt(i, rows) && i != selected
    selected = i
  }

  func horizontal(_ dx: Int) {
    let rows = self.rows
    if settingsView, selected < rows.count, isStepper(rows[selected]) { step(rows[selected], dx) } else { move(dx) }
  }

  func keyPressed(_ t: String) {
    if t == "s" || t == "S" { showSettings(!settingsView); return }
    for (i, r) in rows.enumerated() where r.key == t {
      selected = i
      activate(i)
      return
    }
  }

  func handleKey(_ event: NSEvent) {
    let chars = event.charactersIgnoringModifiers ?? ""
    switch event.keyCode {
    case 126: move(-1)
    case 125: move(1)
    case 123: horizontal(-1)
    case 124: horizontal(1)
    case 36, 76: activate(selected)
    case 53: if settingsView { showSettings(false) } else { close() }
    case 48: break
    default:
      if chars == "k" { move(-1) }
      else if chars == "j" { move(1) }
      else if chars == "h" { horizontal(-1) }
      else if chars == "l" { horizontal(1) }
      else if !chars.isEmpty { keyPressed(chars) }
    }
  }

  // Wheel over a stepper (hovering selects it) steps it, like onWheel in the QML.
  func scroll(_ event: NSEvent) {
    let rows = self.rows
    guard settingsView, selected < rows.count, isStepper(rows[selected]) else { return }
    let dy = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
    if !event.hasPreciseScrollingDeltas {
      if dy != 0 { step(rows[selected], dy > 0 ? 1 : -1) }
      return
    }
    scrollAccum += dy
    if abs(scrollAccum) >= 24 {
      step(rows[selected], scrollAccum > 0 ? 1 : -1)
      scrollAccum = 0
    }
  }
}

// ---- View

struct VisualEffect: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = .popover
    v.blendingMode = .behindWindow
    v.state = .active
    return v
  }
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PanelView: View {
  @ObservedObject var model: PanelModel
  @ObservedObject var timer: TimerService

  let width: CGFloat = 360

  var body: some View {
    let rows = model.rows
    VStack(alignment: .leading, spacing: 0) {
      header
      ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
        let prevGroup = i > 0 ? rows[i - 1].group : nil
        let newGroup = i == 0 || row.group != prevGroup
        let sectionTitle = !row.group.isEmpty && !row.group.hasPrefix("-") ? row.group : ""
        if newGroup && (i > 0 || !sectionTitle.isEmpty) {
          SectionHeader(title: sectionTitle)
        }
        RowView(model: model, row: row, index: i)
      }
      footer(rows)
    }
    .frame(width: width)
    .padding(12)
    .background(VisualEffect())
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
  }

  // ---- Header: live status, or the settings title
  var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(model.settingsView ? "Pomodoro"
           : timer.stopped ? "Pomodoro · " + timer.modeLabel
           : timer.ready ? "Pausen er slut"
           : timer.phaseLabel + " · " + timer.modeLabel)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(timer.onBreak && !model.settingsView ? Color.accentColor : Color.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(model.settingsView ? "Indstillinger"
             : timer.ready ? "--:--"
             : (timer.countingUp ? "↑" : "") + timer.remainingText)
          .font(.system(size: model.settingsView ? 26 : 36, weight: .bold).monospacedDigit())
          .foregroundStyle(timer.paused && !model.settingsView ? Color.secondary : Color.primary)
        Text(model.settingsView || timer.stopped ? ""
             : (timer.paused ? "på pause · " : "") + "runde \(timer.round)"
               + (timer.mode == "flow" ? "" : "/\(timer.modeConfig().rounds)"))
          .font(.system(size: 13))
          .foregroundStyle(Color.secondary)
      }
    }
    .padding(.bottom, 12)
  }

  // ---- Explanation of the selected/hovered row. Fixed height so the panel
  //      doesn't jump as the text changes.
  func footer(_ rows: [PanelRow]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider().padding(.top, 4)
      Text(model.selected < rows.count ? rows[model.selected].info : "")
        .font(.system(size: 12))
        .foregroundStyle(Color.secondary)
        .lineLimit(3)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
        .padding(.horizontal, 8)
      Spacer(minLength: 0)
    }
    .frame(width: width, height: 62, alignment: .topLeading)
  }
}

struct SectionHeader: View {
  let title: String
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider().padding(.top, 4)
      if !title.isEmpty {
        Spacer(minLength: 0)
        Text(title.uppercased())
          .font(.system(size: 10, weight: .bold))
          .tracking(1)
          .foregroundStyle(Color.secondary)
          .padding(.bottom, 3)
      }
    }
    .frame(height: title.isEmpty ? 9 : 26, alignment: .top)
  }
}

struct RowView: View {
  @ObservedObject var model: PanelModel
  let row: PanelRow
  let index: Int
  @State private var hintMidX: CGFloat = .infinity

  var body: some View {
    let hot = model.selected == index && !row.disabled
    let accented = hot || row.current
    let stepper = model.isStepper(row)
    HStack(spacing: 0) {
      Text(row.key)
        .font(.system(size: row.key.count > 1 ? 10 : 13, weight: .bold).monospacedDigit())
        .foregroundStyle(hot ? Color.accentColor : Color.secondary)
        .frame(width: 22, alignment: .leading)
      Image(systemName: row.icon.isEmpty ? "circle" : row.icon)
        .font(.system(size: 14))
        .opacity(row.icon.isEmpty ? 0 : 1)
        .foregroundStyle(accented ? Color.accentColor : Color.primary)
        .frame(width: 22)
      Text(row.label + (row.current ? "  ✓" : ""))
        .font(.system(size: 14, weight: row.current ? .bold : .regular))
        .foregroundStyle(accented ? Color.accentColor : Color.primary)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.leading, 8)
      Spacer(minLength: 8)
      Text(row.hint)
        .font(.system(size: stepper ? 14 : 12).monospacedDigit())
        .foregroundStyle(stepper ? Color.primary : Color.secondary)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("row")).midX } action: { hintMidX = $0 }
    }
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(RoundedRectangle(cornerRadius: 4)
      .fill(hot ? Color.accentColor.opacity(0.16) : Color.clear))
    .opacity(row.disabled ? 0.35 : (row.dim ? 0.55 : 1))
    .contentShape(Rectangle())
    .coordinateSpace(.named("row"))
    .onHover { inside in if inside && !row.disabled { model.selected = index } }
    .onTapGesture(coordinateSpace: .named("row")) { loc in
      // Steppers: left of the value's middle (‹) steps down, right of it (›) up.
      if stepper { model.step(row, loc.x < hintMidX ? -1 : 1) } else { model.activate(index) }
    }
    .pointerStyle(row.disabled ? .default : .link)
  }
}

// ---- Window

final class PanelWindow: NSPanel {
  var onKey: ((NSEvent) -> Void)?
  var onScroll: ((NSEvent) -> Void)?
  override var canBecomeKey: Bool { true }
  override func keyDown(with event: NSEvent) { onKey?(event) }
  override func scrollWheel(with event: NSEvent) { onScroll?(event) }
}

final class PanelController: NSObject, NSWindowDelegate {
  let model: PanelModel
  let window: PanelWindow
  let hosting: NSHostingView<PanelView>
  private var anchorTop: CGFloat = 0
  private var subs: Set<AnyCancellable> = []
  private(set) var lastClosed = Date.distantPast
  var opened: Bool { window.isVisible }
  var anchorRect: () -> NSRect? = { nil }

  init(timer: TimerService) {
    model = PanelModel(timer: timer)
    hosting = NSHostingView(rootView: PanelView(model: model, timer: timer))
    window = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 400),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
    super.init()
    window.isFloatingPanel = true
    window.level = .popUpMenu
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    window.contentView = hosting
    window.delegate = self
    window.onKey = { [weak self] e in self?.model.handleKey(e) }
    window.onScroll = { [weak self] e in self?.model.scroll(e) }
    model.close = { [weak self] in self?.close() }
    // The content height changes with the view and the visible rows; keep the
    // panel's top edge pinned under the menu bar.
    Publishers.Merge(model.objectWillChange, timer.objectWillChange)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.fit() }
      .store(in: &subs)
  }

  func fit() {
    guard window.isVisible else { return }
    let size = hosting.fittingSize
    var f = window.frame
    if abs(f.height - size.height) < 0.5 && abs(f.width - size.width) < 0.5 { return }
    f.size = size
    f.origin.y = anchorTop - size.height
    window.setFrame(f, display: true)
  }

  func open() {
    model.timer.configure()
    model.settingsView = false
    model.selected = 0
    let size = hosting.fittingSize
    // A full menu bar pushes the item off screen; open top right instead.
    var anchor = anchorRect() ?? .zero
    if !NSScreen.screens.contains(where: { $0.frame.intersects(anchor) }), let main = NSScreen.main {
      anchor = NSRect(x: main.visibleFrame.maxX, y: main.visibleFrame.maxY + 4, width: 0, height: 0)
    }
    let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? anchor
    var x = anchor.minX
    x = min(x, visible.maxX - size.width - 6)
    x = max(x, visible.minX + 6)
    anchorTop = anchor.minY - 4
    window.setFrame(NSRect(x: x, y: anchorTop - size.height, width: size.width, height: size.height), display: true)
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    guard window.isVisible else { return }
    window.orderOut(nil)
    lastClosed = Date()
  }

  func toggle() {
    if opened { close() }
    // A click on the menu bar item takes the key focus first and closes the
    // panel; don't reopen it on the same click.
    else if Date().timeIntervalSince(lastClosed) > 0.3 { open() }
  }

  func windowDidResignKey(_ notification: Notification) { close() }
}
