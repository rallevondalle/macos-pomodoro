import AppKit
import UserNotifications

// The app binary doubles as its CLI (the Omarchy version's IPC handler):
//   pomodoro toggle | stop | skip | status | mode | panel
//   pomodoro focus classic|deep|flow · takeBreak 10 · lunch · setMode deep
//   pomodoro dismissBreakScreen · cycleBreakScreen · toggleAutoRestart
// It talks to the running menu bar app over distributed notifications.

let commandName = Notification.Name("com.rallevondalle.pomodoro.command")
let replyName = Notification.Name("com.rallevondalle.pomodoro.reply")
let commands: Set<String> = [
  "toggle", "stop", "skip", "focus", "takeBreak", "lunch", "dismissBreakScreen",
  "toggleAutoRestart", "cycleBreakScreen", "setMode", "mode", "status", "panel", "debug"
]

func runCommand(_ args: [String], timer: TimerService, panel: PanelController) -> String {
  let arg = args.count > 1 ? args[1] : ""
  switch args.first ?? "" {
  case "toggle": timer.toggle()
  case "stop": timer.stop()
  case "skip": timer.skip()
  case "focus": timer.startFocus(arg)
  case "takeBreak": timer.takeBreak(Double(arg) ?? 5)
  case "lunch": timer.takeBreak(Double(timer.lunchMinutes))
  case "dismissBreakScreen": timer.dismissBreakScreen()
  case "toggleAutoRestart": timer.toggleAutoRestart(); return timer.autoRestart ? "true" : "false"
  case "cycleBreakScreen": timer.cycleBreakScreen(1); return timer.breakScreenMode
  case "setMode": timer.setMode(arg)
  case "mode": return timer.mode
  case "status": timer.tick(); return timer.status_()
  case "panel": panel.toggle()
  case "debug":
    return NSApp.windows.map { "\(type(of: $0)) #\($0.windowNumber) \($0.frame) visible=\($0.isVisible) onScreen=\($0.occlusionState.contains(.visible))" }
      .joined(separator: "\n")
  default: return "ukendt kommando"
  }
  return ""
}

func runCLI(_ args: [String]) -> Never {
  let id = UUID().uuidString
  let center = DistributedNotificationCenter.default()
  var reply: String?
  let token = center.addObserver(forName: replyName, object: id, queue: nil) { n in
    reply = (n.userInfo?["reply"] as? String) ?? ""
  }
  center.postNotificationName(commandName, object: id, userInfo: ["args": args], deliverImmediately: true)
  let until = Date().addingTimeInterval(2)
  while reply == nil && Date() < until {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
  }
  center.removeObserver(token)
  guard let r = reply else {
    FileHandle.standardError.write("Pomodoro kører ikke (open -a Pomodoro)\n".data(using: .utf8)!)
    exit(1)
  }
  if !r.isEmpty { print(r) }
  exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  let timer = TimerService.shared
  var panel: PanelController!
  var statusBar: StatusBarController!
  var breakScreen: BreakScreenController!

  func applicationWillTerminate(_ notification: Notification) { timer.pauseForQuit() }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let nc = UNUserNotificationCenter.current()
    nc.delegate = self
    nc.requestAuthorization(options: [.alert]) { _, _ in }

    timer.start()
    panel = PanelController(timer: timer)
    statusBar = StatusBarController(timer: timer, panel: panel)
    breakScreen = BreakScreenController(timer: timer)

    DistributedNotificationCenter.default().addObserver(
      forName: commandName, object: nil, queue: .main) { [weak self] n in
      guard let self = self, let args = n.userInfo?["args"] as? [String] else { return }
      let reply = runCommand(args, timer: self.timer, panel: self.panel)
      DistributedNotificationCenter.default().postNotificationName(
        replyName, object: n.object as? String, userInfo: ["reply": reply], deliverImmediately: true)
    }
  }

  // Show the banners while the app is frontmost too (it is, during the break screen).
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list])
  }
}

let args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, commands.contains(first) { runCLI(args) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
