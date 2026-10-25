import AppKit
import Foundation
import UserNotifications

// Port of Service.qml. Single timer for the menu bar item, the panel and the
// break screen. State is deadline-based and persisted, so sleep, quitting and
// relaunching don't lose or skew the countdown.
//
// Design choices, from the research on breaks:
// - Systematic breaks (Pomodoro) give less fatigue and better concentration
//   than "I'll break when I feel like it" (Biwer et al. 2023), so focus
//   always rolls straight into a break.
// - Flowtime (self-chosen focus length, break proportional to it) did as
//   well on productivity with a slower rise in fatigue (2025 follow-up),
//   so it is offered as a mode: break = focus / 5.
// - Longer breaks restore more after demanding work (Albulescu et al. 2022),
//   hence the deep mode and the long breaks.
// - A break that ends while you're away shouldn't start the next focus
//   without you, so a finished break waits in "ready" for a click. With the
//   break screen on, the screen stays up and counts the overtime until you
//   dismiss it, so a longer break than planned is still a break.

struct ModeConfig {
  var work: Double
  var shortBreak: Double
  var longBreak: Double
  var rounds: Int
}

func nowMillis() -> Double { Date().timeIntervalSince1970 * 1000 }

// JavaScript's Math.round, so the numbers match the Omarchy version.
func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

func twoDigits(_ n: Int) -> String { (n < 10 ? "0" : "") + String(n) }

final class TimerService: ObservableObject {
  static let shared = TimerService()

  let stateDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Pomodoro")
  var statePath: URL { stateDir.appendingPathComponent("state.json") }

  // Classic mode comes from `defaults write com.rallevondalle.pomodoro`; the others are fixed.
  @Published var config = ModeConfig(work: 25, shortBreak: 5, longBreak: 15, rounds: 4)
  let flowNudgeMinutes: Double = 90

  // mode: classic | deep | flow
  // status: stopped | running | paused | ready (break over, waiting for you)
  // phase: work | short | long | manual
  @Published var mode = "classic"
  @Published var status = "stopped"
  @Published var phase = "work"
  @Published var round = 1
  @Published var deadlineMs: Double = 0
  @Published var remainingMs: Double = 0
  @Published var durationMs: Double = 0
  @Published var startedMs: Double = 0      // flow: start of the current running stretch
  @Published var elapsedMs: Double = 0      // flow: focus time banked before that stretch
  @Published var flowNudged = false
  @Published var overtimeSinceMs: Double = 0  // > 0: break over, break screen held up

  // Panel preferences, edited from the panel's settings view.
  @Published var lunchMinutes = 45
  @Published var hiddenItems: [String] = []
  // When breaks take over the screen: deep | all | off
  @Published var breakScreenMode = "deep"
  // Dismissing the held break screen starts the next focus right away.
  @Published var autoRestart = true

  // Tip shown in the break notification and on the break screen.
  @Published var breakTip = ""
  @Published var nowMs: Double = nowMillis()
  private(set) var loaded = false
  private var ticker: Timer?

  // Running breaks take over the screen (see BreakScreen.swift), and the screen
  // stays up counting overtime after the break until it is dismissed.
  var breakScreenWanted: Bool {
    breakScreenMode == "all" || (breakScreenMode == "deep" && mode == "deep")
  }
  var overtime: Bool { ready && overtimeSinceMs > 0 }
  var breakScreenActive: Bool { (onBreak && running && breakScreenWanted) || overtime }
  var overtimeText: String {
    let s = max(0, Int(((nowMs - overtimeSinceMs) / 1000).rounded(.down)))
    return "+" + twoDigits(s / 60) + ":" + twoDigits(s % 60)
  }

  var running: Bool { status == "running" }
  var paused: Bool { status == "paused" }
  var stopped: Bool { status == "stopped" }
  var ready: Bool { status == "ready" }
  var onBreak: Bool { !stopped && !ready && phase != "work" }
  var countingUp: Bool { mode == "flow" && phase == "work" && (running || paused) }

  var flowElapsedMs: Double { elapsedMs + (running && countingUp ? nowMs - startedMs : 0) }
  var displaySeconds: Int {
    let v = countingUp
      ? (flowElapsedMs / 1000).rounded(.down)
      : ((running ? deadlineMs - nowMs : (paused ? remainingMs : phaseMs("work"))) / 1000).rounded(.up)
    return max(0, Int(v))
  }
  var remainingText: String {
    let s = displaySeconds
    return twoDigits(s / 60) + ":" + twoDigits(s % 60)
  }
  var flowBreakMinutes: Int { minutes(flowBreakMs(flowElapsedMs)) }
  var phaseLabel: String {
    ["work": "Fokus", "short": "Pause", "long": "Lang pause", "manual": "Pause"][phase] ?? "Fokus"
  }
  var modeLabel: String {
    switch mode {
    case "classic": return "Klassisk " + fmt(config.work) + "/" + fmt(config.shortBreak)
    case "deep": return "Dyb 50/10"
    case "flow": return "Flow"
    default: return mode
    }
  }

  let shortTips = [
    "Rejs dig og gå lidt rundt — bevægelse giver mest energi tilbage.",
    "Kig ud ad vinduet, langt væk, og giv øjnene fri fra skærmen.",
    "Drik et glas vand.",
    "Lad telefonen ligge — scrolling genoplader dårligere end en rigtig pause.",
    "Stræk nakke, skuldre og ryg.",
    "Luk øjnene og tag et par langsomme, dybe vejrtrækninger."
  ]
  let longTips = [
    "Gå udenfor, hvis du kan — frisk luft og dagslys.",
    "Spis eller drik noget, væk fra skærmen.",
    "Tag en snak med nogen — socialt samvær genoplader godt.",
    "Gå en rigtig tur og tænk på noget helt andet end arbejdet."
  ]

  func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(v)
  }

  func configure() {
    let d = UserDefaults.standard
    func num(_ key: String, _ fallback: Double) -> Double {
      let v = d.double(forKey: key)
      return v.isFinite && v > 0 ? v : fallback
    }
    let next = ModeConfig(
      work: num("workMinutes", 25),
      shortBreak: num("shortBreakMinutes", 5),
      longBreak: num("longBreakMinutes", 15),
      rounds: Int(jsRound(num("roundsPerLongBreak", 4))))
    if next.work != config.work || next.shortBreak != config.shortBreak
        || next.longBreak != config.longBreak || next.rounds != config.rounds {
      config = next
    }
  }

  func modeConfig() -> ModeConfig {
    if mode == "deep" { return ModeConfig(work: 50, shortBreak: 10, longBreak: 30, rounds: 2) }
    return config
  }

  func phaseMs(_ p: String) -> Double {
    let c = modeConfig()
    let min = p == "work" ? c.work : (p == "long" ? c.longBreak : c.shortBreak)
    return min * 60 * 1000
  }

  func flowBreakMs(_ focusMs: Double) -> Double {
    let min = Swift.min(30, Swift.max(2, jsRound(focusMs / 60000 / 5)))
    return min * 60 * 1000
  }

  func minutes(_ ms: Double) -> Int { Int(jsRound(ms / 60000)) }

  func beginWork() {
    configure()
    let now = nowMillis()
    overtimeSinceMs = 0
    phase = "work"
    status = "running"
    if mode == "flow" {
      startedMs = now
      elapsedMs = 0
      flowNudged = false
      deadlineMs = 0
      durationMs = 0
      notify("Fokus — runde \(round)", "Flow: arbejd så længe det kører, og tag pause når du mister fokus.")
    } else {
      durationMs = phaseMs("work")
      deadlineMs = now + durationMs
      remainingMs = durationMs
      notify("Fokus — runde \(round)", "\(minutes(durationMs)) minutter. Én opgave, notifikationer væk.")
    }
    nowMs = now
    save()
  }

  // Starts a break that began at `fromMs` (the work deadline, so time asleep
  // or away counts as break). If it already ran out, go straight to ready.
  func beginBreak(_ kind: String, _ ms: Double, _ fromMs: Double, _ title: String) {
    overtimeSinceMs = 0
    phase = kind
    status = "running"
    durationMs = ms
    deadlineMs = fromMs + ms
    nowMs = nowMillis()
    if deadlineMs <= nowMs {
      breakOver()
      return
    }
    let tips = kind == "long" || ms >= 15 * 60000 ? longTips : shortTips
    let minute = Calendar.current.component(.minute, from: Date())
    breakTip = tips[(round + minute) % tips.count]
    notify(title + " · \(minutes(ms)) min", breakTip)
    save()
  }

  func finishWork(_ atMs: Double) {
    let completed = round
    round = round + 1
    if mode == "flow" {
      beginBreak("short", flowBreakMs(flowElapsedMs), atMs,
        "Godt arbejde (\(minutes(flowElapsedMs)) min)")
      return
    }
    let c = modeConfig()
    let kind = completed % c.rounds == 0 ? "long" : "short"
    beginBreak(kind, phaseMs(kind), atMs, kind == "long" ? "Lang pause" : "Pause")
  }

  // Overtime is set before the status changes, so the break screen stays up
  // through the switch instead of closing for a frame and fading in again.
  func breakOver() {
    if breakScreenWanted { overtimeSinceMs = deadlineMs }
    status = "ready"
    phase = "work"
    nowMs = nowMillis()
    if breakScreenWanted {
      notify("Pausen er slut", autoRestart
        ? "Esc eller Enter starter runde \(round)."
        : "Enter starter runde \(round), Esc lukker pauseskærmen.")
    } else {
      notify("Pausen er slut", "Klik på timeren i menulinjen for at starte runde \(round).")
    }
    save()
  }

  // Closes the held break screen: starts the next focus with autoRestart,
  // otherwise the timer keeps waiting in "ready".
  func dismissBreakScreen() {
    if overtimeSinceMs <= 0 { return }
    if autoRestart { beginWork(); return }
    overtimeSinceMs = 0
    save()
  }

  func toggleAutoRestart() {
    autoRestart = !autoRestart
    save()
  }

  // ---- Actions (menu bar clicks, panel, CLI)

  func toggle() {
    let now = nowMillis()
    if stopped { round = 1; beginWork(); return }
    if ready { beginWork(); return }
    // Flow has no use for pausing: a click switches between the count-up
    // focus and its computed break.
    if mode == "flow" {
      if phase == "work" { finishWork(now) } else { beginWork() }
      return
    }
    if running {
      if countingUp { elapsedMs += now - startedMs } else { remainingMs = max(0, deadlineMs - now) }
      status = "paused"
    } else {
      if countingUp { startedMs = now } else { deadlineMs = now + remainingMs }
      status = "running"
    }
    nowMs = now
    save()
  }

  func startFocus(_ newMode: String?) {
    if let newMode = newMode, !newMode.isEmpty, newMode != mode {
      guard ["classic", "deep", "flow"].contains(newMode) else { return }
      mode = newMode
      round = 1
    } else if stopped {
      round = 1
    }
    beginWork()
  }

  // A break inserted mid-focus discards the unfinished focus; the round
  // number stays, so the cycle towards the long break isn't cheated.
  func takeBreak(_ min: Double) {
    let ms = max(1, min.isFinite && min != 0 ? min : 5) * 60000
    beginBreak("manual", ms, nowMillis(), "Pause")
  }

  func skip() {
    if stopped { return }
    if ready || onBreak { beginWork() } else { finishWork(nowMillis()) }
  }

  func stop() {
    overtimeSinceMs = 0
    status = "stopped"
    phase = "work"
    round = 1
    save()
  }

  func setMode(_ newMode: String) {
    if newMode != "classic" && newMode != "deep" && newMode != "flow" { return }
    if newMode == mode { return }
    mode = newMode
    if !stopped && phase == "work" { startFocus(newMode) } else { save() }
  }

  func setLunchMinutes(_ value: Int) {
    lunchMinutes = max(15, min(120, value))
    save()
  }

  func cycleBreakScreen(_ delta: Int) {
    let order = ["deep", "all", "off"]
    let n = order.count
    let i = order.firstIndex(of: breakScreenMode) ?? 0
    breakScreenMode = order[((i + (delta < 0 ? -1 : 1)) % n + n) % n]
    save()
  }

  func toggleHidden(_ id: String) {
    var next = hiddenItems
    if let i = next.firstIndex(of: id) { next.remove(at: i) } else { next.append(id) }
    hiddenItems = next
    save()
  }

  func adjust(_ min: Double) {
    if stopped || ready || countingUp { return }
    let delta = min * 60000
    let now = nowMillis()
    if running {
      deadlineMs = max(now + 1000, deadlineMs + delta)
      durationMs = max(durationMs, deadlineMs - now)
    } else {
      remainingMs = max(1000, remainingMs + delta)
      durationMs = max(durationMs, remainingMs)
    }
    nowMs = now
    save()
  }

  func tick() {
    nowMs = nowMillis()
    if !running { return }
    if countingUp {
      if !flowNudged && flowElapsedMs >= flowNudgeMinutes * 60000 {
        flowNudged = true
        save()
        notify("\(Int(flowNudgeMinutes)) minutters fokus", "Tid til en pause? Midterklik på timeren for at tage den.")
      }
    } else if nowMs >= deadlineMs {
      if phase == "work" { finishWork(deadlineMs) } else { breakOver() }
    }
  }

  func status_() -> String {
    "\(mode) \(status) \(phase) r\(round) \(remainingText)"
  }

  func notify(_ title: String, _ body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = "pomodoro"
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  // ---- Persistence

  func save() {
    guard loaded else { return }
    let s: [String: Any] = [
      "mode": mode, "status": status, "phase": phase, "round": round,
      "deadlineMs": deadlineMs, "remainingMs": remainingMs, "durationMs": durationMs,
      "startedMs": startedMs, "elapsedMs": elapsedMs, "flowNudged": flowNudged,
      "overtimeSinceMs": overtimeSinceMs,
      "lunchMinutes": lunchMinutes, "hiddenItems": hiddenItems,
      "breakScreenMode": breakScreenMode, "autoRestart": autoRestart, "breakTip": breakTip
    ]
    do {
      try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
      var data = try JSONSerialization.data(withJSONObject: s, options: [.sortedKeys])
      data.append(0x0A)
      try data.write(to: statePath, options: .atomic)
    } catch {
      NSLog("pomodoro: kunne ikke gemme tilstand: \(error)")
    }
  }

  func restore() {
    if let data = try? Data(contentsOf: statePath),
       let s = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
      func num(_ key: String) -> Double { (s[key] as? NSNumber)?.doubleValue ?? 0 }
      if let m = s["mode"] as? String, ["classic", "deep", "flow"].contains(m) { mode = m }
      if num("lunchMinutes") > 0 { lunchMinutes = Int(num("lunchMinutes")) }
      if let h = s["hiddenItems"] as? [String] { hiddenItems = h }
      if let b = s["breakScreenMode"] as? String, ["deep", "all", "off"].contains(b) { breakScreenMode = b }
      if let a = s["autoRestart"] as? Bool { autoRestart = a }
      if let t = s["breakTip"] as? String, !t.isEmpty { breakTip = t }
      if let st = s["status"] as? String, ["running", "paused", "ready"].contains(st) {
        phase = (s["phase"] as? String) ?? "work"
        round = max(1, Int(num("round")))
        deadlineMs = num("deadlineMs")
        remainingMs = num("remainingMs")
        durationMs = num("durationMs")
        startedMs = num("startedMs")
        elapsedMs = num("elapsedMs")
        flowNudged = (s["flowNudged"] as? Bool) ?? false
        overtimeSinceMs = st == "ready" ? num("overtimeSinceMs") : 0
        status = st
      }
    }
    loaded = true
    tick()
  }

  func start() {
    configure()
    restore()
    let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self = self, self.loaded, self.running || self.overtime else { return }
      self.tick()
    }
    RunLoop.main.add(t, forMode: .common)
    ticker = t
    // Time asleep counts as break time; catch up right away on wake.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.tick()
    }
  }
}
