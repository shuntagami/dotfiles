// Minimal native click adapter for Raycast's WebKit menus. No keyboard capture.
import ApplicationServices
import AppKit
import Foundation

guard AXIsProcessTrusted() else {
    fputs("Allow the terminal running setup in macOS Accessibility, then rerun.\n", stderr)
    exit(3)
}
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--check" {
    print("Accessibility ready")
    exit(0)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.raycast.macos").first else {
    fputs("Raycast is not running; no input was sent.\n", stderr)
    exit(3)
}
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func label(_ element: AXUIElement) -> String {
    for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
        if let text = attribute(element, key) as? String, !text.isEmpty { return text }
    }
    if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole {
        return attribute(element, kAXValueAttribute) as? String ?? ""
    }
    return ""
}
func walk(_ element: AXUIElement, path: [Int] = [], depth: Int = 0,
          visit: (AXUIElement, [Int]) -> Void) {
    guard depth <= 18 else { return }
    visit(element, path)
    for (index, child) in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).enumerated() {
        walk(child, path: path + [index + 1], depth: depth + 1, visit: visit)
    }
}
let arguments = CommandLine.arguments
if arguments.count >= 3 && ["--find-window", "--legal-check", "--import-counts"].contains(arguments[1]) {
    let application = AXUIElementCreateApplication(app.processIdentifier)
    let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard let window = windows.first(where: { label($0) == arguments[2] }) else {
        fputs("Raycast window unavailable.\n", stderr); exit(3)
    }
    if arguments[1] == "--find-window" {
        guard arguments.count == 6 else { exit(1) }
        walk(window) { element, path in
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let text = label(element)
            if (arguments[3] == "any" || role == arguments[3]) &&
                (arguments[4].isEmpty || text == arguments[4] || (arguments[5] == "1" && text.hasPrefix(arguments[4]))) {
                print(path.isEmpty ? "root" : path.map(String.init).joined(separator: "."))
            }
        }
    } else if arguments[1] == "--legal-check" {
        var needsConsent = false
        walk(window) { element, _ in
            let text = label(element).lowercased()
            if text.contains("agree to") || text.contains("terms of service") { needsConsent = true }
        }
        print(needsConsent ? "required" : "ready")
    } else {
        var texts: [String] = []
        walk(window) { element, _ in
            if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole { texts.append(label(element)) }
        }
        let text = texts.joined(separator: " ")
        func count(_ pattern: String) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return "0" }
            return String(text[range])
        }
        print(count("([0-9]+)\\s+(?:snippet\\s*s?|quicklink\\s*s?)\\s+added") + "|" +
              count("([0-9]+)\\s+duplicate\\s*s?\\s+skipped"))
    }
    exit(0)
}
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--focus" {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    var focusedPID: pid_t = 0
    if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
       let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
        AXUIElementGetPid(unsafeBitCast(focused, to: AXUIElement.self), &focusedPID)
    }
    // The launcher is a non-activating panel: Chrome can remain the frontmost
    // application while Raycast owns keyboard focus.
    let ownApplication = AXUIElementCreateApplication(app.processIdentifier)
    var ownWindow: CFTypeRef?
    var windowFocused: CFTypeRef?
    var knownWindow = "none"
    if AXUIElementCopyAttributeValue(ownApplication, kAXFocusedWindowAttribute as CFString, &ownWindow) == .success,
       let ownWindow, CFGetTypeID(ownWindow) == AXUIElementGetTypeID() {
        let element = unsafeBitCast(ownWindow, to: AXUIElement.self)
        let title = label(element)
        if ["Main Window", "Settings", "Open", "Select file"].contains(title) { knownWindow = title }
        AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &windowFocused)
    }
    guard focusedPID == app.processIdentifier || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.raycast.macos" else {
        let keyState = (windowFocused as? NSNumber)?.boolValue.description ?? "unavailable"
        fputs("Raycast does not own keyboard focus (window \(knownWindow), focused=\(keyState)); no text was sent.\n", stderr)
        exit(3)
    }
    print("Raycast keyboard focus verified")
    exit(0)
}
guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]), x.isFinite,
      let y = Double(CommandLine.arguments[2]), y.isFinite else {
    fputs("Expected a finite x/y click position.\n", stderr)
    exit(1)
}
let point = CGPoint(x: x, y: y)
var target: AXUIElement?
var targetPID: pid_t = 0
if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(x), Float(y), &target) == .success,
   let target {
    AXUIElementGetPid(target, &targetPID)
}
guard targetPID == app.processIdentifier else {
    let owner = NSRunningApplication(processIdentifier: targetPID)?.localizedName ?? "another window"
    fputs("The click target belongs to \(owner), not Raycast; no click was sent.\n", stderr)
    exit(3)
}
CGWarpMouseCursorPosition(point)
Thread.sleep(forTimeInterval: 0.04)
guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                         mouseCursorPosition: point, mouseButton: .left),
      let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                       mouseCursorPosition: point, mouseButton: .left) else {
    fputs("Could not prepare a native click.\n", stderr)
    exit(1)
}
down.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.04)
up.post(tap: .cghidEventTap)
