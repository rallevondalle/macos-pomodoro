import AppKit
import SwiftUI

// Draws the app icon: a tomato-red squircle with the timer symbol, on the
// standard macOS grid (824 pt squircle centred on a 1024 pt canvas).
// Usage: tools/make-icon.sh (compiles this and builds AppIcon.icns).

struct Icon: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 185, style: .continuous)
        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.30),
                                      Color(red: 0.86, green: 0.16, blue: 0.20),
                                      Color(red: 0.48, green: 0.08, blue: 0.28)],
                             startPoint: .topLeading, endPoint: .bottomTrailing))
      RoundedRectangle(cornerRadius: 185, style: .continuous)
        .fill(RadialGradient(colors: [.white.opacity(0.35), .clear],
                             center: UnitPoint(x: 0.3, y: 0.15), startRadius: 0, endRadius: 520))
      RoundedRectangle(cornerRadius: 185, style: .continuous)
        .strokeBorder(.white.opacity(0.25), lineWidth: 3)
      Image(systemName: "timer")
        .font(.system(size: 470, weight: .semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
    .frame(width: 824, height: 824)
    .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
    .frame(width: 1024, height: 1024)
  }
}

let out = CommandLine.arguments[1]
MainActor.assumeIsolated {
  let r = ImageRenderer(content: Icon())
  r.scale = 1
  let rep = NSBitmapImageRep(cgImage: r.cgImage!)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
