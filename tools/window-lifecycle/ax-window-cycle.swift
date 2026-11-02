import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func refuse(_ message: String) -> Never {
    fputs("REFUSED: \(message)\n", stderr)
    exit(2)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3,
      let pid = Int32(args[0]), pid > 0,
      let windowID = Int(args[1]), windowID > 0 else {
    refuse("usage: ax-window-cycle PID WINDOW_ID EXACT_TITLE [--cycles N] [--fullscreen-cycles N]")
}
let title = args[2]
var cycles = 1, fullscreenCycles = 0, index = 3
while index < args.count {
    guard index + 1 < args.count, let count = Int(args[index + 1]), (0...20).contains(count) else {
        refuse("cycle counts must be integers from 0 to 20")
    }
    switch args[index] {
    case "--cycles": cycles = count
    case "--fullscreen-cycles": fullscreenCycles = count
    default: refuse("unknown option")
    }
    index += 2
}
guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
    refuse("Accessibility and Screen Recording permissions are required")
}
func visibleBounds() -> CGRect? {
    let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    guard let row = rows.first(where: { $0[kCGWindowNumber as String] as? Int == windowID }),
          row[kCGWindowOwnerPID as String] as? Int == Int(pid),
          row[kCGWindowName as String] as? String == title,
          row[kCGWindowLayer as String] as? Int == 0,
          let raw = row[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: raw as CFDictionary)
}
guard let original = visibleBounds() else { refuse("initial PID/window/title/layer mismatch") }
let app = AXUIElementCreateApplication(pid)
var rawWindows: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
      let windows = rawWindows as? [AXUIElement] else { refuse("AX windows unavailable") }
let matches = windows.filter { window in
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success
        && value as? String == title
}
guard matches.count == 1 else { refuse("AX target must have a unique exact title in the verified process") }
let window = matches[0]
func boolValue(_ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success else { return nil }
    return (value as? NSNumber)?.boolValue
}
func waitFor(_ description: String, _ condition: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: 7)
    repeat {
        if condition() { return }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    } while Date() < deadline
    refuse("timed out: \(description)")
}
func set(_ attribute: String, _ value: Bool) {
    var settable: DarwinBoolean = false
    guard AXUIElementIsAttributeSettable(window, attribute as CFString, &settable) == .success,
          settable.boolValue else { refuse("attribute is not settable: \(attribute)") }
    let status = AXUIElementSetAttributeValue(window, attribute as CFString,
                                            value ? kCFBooleanTrue : kCFBooleanFalse)
    guard status == .success else { refuse("AX set failed: \(attribute), status=\(status.rawValue)") }
    waitFor("\(attribute)=\(value)") { boolValue(attribute) == value }
}
func settleFullscreen(_ value: Bool) {
    // AX can change before AppKit finishes its transition. Sending the reverse
    // request immediately can be ignored even though AX returns success.
    let began = Date()
    var previous = visibleBounds(), unchangedSince = Date()
    waitFor("settled native fullscreen transition") {
        let current = visibleBounds()
        if current != previous { previous = current; unchangedSince = Date() }
        return current != nil && boolValue("AXFullScreen") == value
            && Date().timeIntervalSince(began) >= 2
            && Date().timeIntervalSince(unchangedSince) >= 1
    }
}
func emit(_ result: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}
guard boolValue(kAXMinimizedAttribute as String) == false else { refuse("initial target must not be minimized") }
for cycle in 0..<fullscreenCycles {
    set("AXFullScreen", true)
    settleFullscreen(true)
    set("AXFullScreen", false)
    settleFullscreen(false)
    waitFor("fullscreen return geometry") { visibleBounds() == original }
    emit(["phase": "native-fullscreen", "cycle": cycle + 1, "returned_geometry": true])
}
for cycle in 0..<cycles {
    set(kAXMinimizedAttribute as String, true)
    waitFor("minimized target absent from on-screen list") { visibleBounds() == nil }
    set(kAXMinimizedAttribute as String, false)
    waitFor("restored exact target and geometry") { visibleBounds() == original }
    emit(["phase": "AX-only", "cycle": cycle + 1,
          "minimized_readback": true, "restored_readback": false,
          "same_window_visible": true, "returned_geometry": true])
}
