// Keep MonitorControl's brightness policy in step with the display layout.
// Uses the same private brightness/name APIs as MonitorControl 4.x.
import AppKit
import CoreGraphics
import Foundation

@_silgen_name("DisplayServicesGetBrightness")
func getBrightness(_ display: CGDirectDisplayID, _ value: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
func setBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Int32
@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func displayInfo(_ display: CGDirectDisplayID) -> Unmanaged<CFDictionary>?

let domain = "app.monitorcontrol.MonitorControl"
let state = UserDefaults(suiteName: "local.dotfiles.monitorcontrol-mode")!

struct Screen {
    let id: CGDirectDisplayID
    let builtIn: Bool
    let mirror: CGDirectDisplayID
    let mirrored: Bool
    let suffix: String?
}

/// Reads the localized display name used by MonitorControl's preference keys.
func rawName(_ id: CGDirectDisplayID) -> String? {
    guard let info = displayInfo(id)?.takeRetainedValue() as? [String: Any],
          let names = info["DisplayProductName"] as? [String: String] else { return nil }
    return names[Locale.current.identifier] ?? names["en_US"] ?? names.values.first
}

/// Keeps every online display, even when its preference-key name is unavailable.
func screens() -> [Screen] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map { id in
        var name = rawName(id)
        let mirror = CGDisplayMirrorsDisplay(id)
        if mirror != 0 {
            // Both names are needed to reproduce MonitorControl's mirror key.
            name = name.flatMap { ownName in rawName(mirror).map { ownName + " | " + $0 } }
        }
        let suffix = name.map { "(\($0.filter { !$0.isWhitespace })\(CGDisplayVendorNumber(id))\(CGDisplayModelNumber(id))@\(id))" }
        return Screen(id: id, builtIn: CGDisplayIsBuiltin(id) != 0, mirror: mirror,
                      mirrored: CGDisplayIsInMirrorSet(id) != 0 || CGDisplayIsInHWMirrorSet(id) != 0,
                      suffix: suffix)
    }
}

/// Classifies the topology without relying on display names.
func mode(_ displays: [Screen]) -> String {
    guard displays.contains(where: { !$0.builtIn }) else { return "laptop" }
    return displays.contains(where: { $0.builtIn && $0.mirrored }) ? "mirror" : "extended"
}

/// Builds shared settings and any display-specific keys whose names are known.
func preferences(_ displays: [Screen]) -> [String: Any] {
    let mirror = mode(displays) == "mirror"
    var values: [String: Any] = [
        "enableBrightnessSync": !mirror,
        "keyboardBrightness": 0, // Standard brightness keys.
        "multiKeyboardBrightness": 1, // All enabled displays.
        "hideAppleFromMenu": mirror,
        "multiSliders": mirror ? 0 : 2, // Combined sliders outside mirroring.
        // Gamma dimming can also dim the mirrored framebuffer. Use DDC only.
        "disableCombinedBrightness": mirror,
    ]
    for display in displays {
        if let suffix = display.suffix {
            values["isDisabled" + suffix] = mirror && display.builtIn
        }
    }
    return values
}

/// Reads one value from MonitorControl's preference domain.
func readPref(_ key: String) -> Any? {
    CFPreferencesCopyAppValue(key as CFString, domain as CFString)
}

/// Updates one key without replacing unrelated application preferences.
func writePref(_ key: String, _ value: Any) {
    CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain as CFString)
}

/// Reads physical Apple-panel brightness, returning nil for unsupported displays.
func brightness(_ id: CGDirectDisplayID) -> Float? {
    var value: Float = 0
    return getBrightness(id, &value) == 0 ? value : nil
}

/// Launches an executable and reports both launch errors and nonzero exit status.
func runCommand(_ executable: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        fputs("Could not launch \(executable): \(error)\n", stderr)
        return false
    }
}

/// Returns false when Launch Services cannot reopen MonitorControl, allowing retries.
@discardableResult
func openMonitorControl() -> Bool {
    runCommand("/usr/bin/open", ["-g", "-a", "MonitorControl"])
}

/// Restores an exact saved zero; the visibility floor applies only to external sync.
func restoredBrightness(external: Float?, saved: Float) -> Float {
    if let external = external { return max(0.05, min(1, external)) }
    return max(0, min(1, saved))
}

/// Applies a stable topology while MonitorControl is stopped, then restarts it.
func apply(_ displays: [Screen]) -> Bool {
    guard !displays.isEmpty else { return false }
    let currentMode = mode(displays)
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: domain)
    for app in apps { _ = app.terminate() }
    let deadline = Date().addingTimeInterval(4)
    while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard apps.allSatisfy({ $0.isTerminated }) else {
        fputs("MonitorControl did not quit; will retry without overwriting its preferences.\n", stderr)
        return false
    }
    guard signature(screens()) == signature(displays) else {
        openMonitorControl()
        return false
    }
    CFPreferencesAppSynchronize(domain as CFString)
    // Keep this flag while the lid is closed, so reopening the laptop after
    // unplugging its monitor still restores a backlight we previously blanked.
    let wasBlanked = state.object(forKey: "builtInBlanked") as? Bool
        ?? (state.string(forKey: "mode") == "mirror")
    for display in displays where display.builtIn {
        if currentMode == "mirror" {
            if !wasBlanked, let value = brightness(display.id) {
                state.set(value, forKey: "builtInBrightness")
            }
        } else if currentMode == "extended" || wasBlanked {
            let external = displays.first(where: { !$0.builtIn })
            let externalValue = external?.suffix.flatMap { readPref("value16" + $0) as? NSNumber }?.floatValue
            let saved = (!wasBlanked ? brightness(display.id) : nil)
                ?? (state.object(forKey: "builtInBrightness") as? NSNumber)?.floatValue ?? 0.5
            let target = restoredBrightness(external: externalValue, saved: saved)
            guard setBrightness(display.id, target) == 0 else {
                openMonitorControl()
                return false
            }
            if let suffix = display.suffix { writePref("value16" + suffix, target) }
            state.set(false, forKey: "builtInBlanked")
        }
    }
    for (key, value) in preferences(displays) { writePref(key, value) }
    guard CFPreferencesAppSynchronize(domain as CFString) else {
        openMonitorControl()
        return false
    }
    // Disable synchronization before blanking the panel, so the external
    // monitor never receives the built-in display's transition to zero.
    if currentMode == "mirror" {
        guard signature(screens()) == signature(displays) else {
            openMonitorControl()
            return false
        }
        for display in displays where display.builtIn {
            state.set(true, forKey: "builtInBlanked")
            state.synchronize()
            guard setBrightness(display.id, 0) == 0 else {
                openMonitorControl()
                return false
            }
        }
    }
    state.set(currentMode, forKey: "mode")
    state.synchronize()
    guard openMonitorControl() else { return false }
    print("Applied \(currentMode) brightness policy")
    fflush(stdout)
    return true
}

/// Includes name availability so recovering display metadata triggers reapplication.
func signature(_ displays: [Screen]) -> String {
    displays.map { "\($0.id):\($0.builtIn):\($0.mirror):\($0.mirrored):\($0.suffix ?? "unknown")" }.sorted().joined(separator: ";")
}

/// Prints the detected topology, panel brightness, and effective managed settings.
func status() {
    let displays = screens()
    CFPreferencesAppSynchronize(domain as CFString)
    print("mode=\(mode(displays))")
    for display in displays {
        let disabled = display.suffix.flatMap { readPref("isDisabled" + $0) }
        print("\(display.suffix ?? "display \(display.id)") builtIn=\(display.builtIn) brightness=\(brightness(display.id).map(String.init(describing:)) ?? "DDC") disabled=\(String(describing: disabled))")
    }
    for key in ["enableBrightnessSync", "keyboardBrightness", "multiKeyboardBrightness", "multiSliders"] {
        print("\(key)=\(String(describing: readPref(key)))")
    }
}

/// Exercises topology decisions, zero restoration, and subprocess failure handling.
func selfTest() {
    let laptop = Screen(id: 1, builtIn: true, mirror: 0, mirrored: false, suffix: "(Laptop)")
    let mirroredLaptop = Screen(id: 1, builtIn: true, mirror: 2, mirrored: true, suffix: "(Laptop|External)")
    let external = Screen(id: 2, builtIn: false, mirror: 0, mirrored: false, suffix: "(External)")
    for (layout, expected) in [([laptop], "laptop"), ([laptop, external], "extended"),
                               ([mirroredLaptop, external], "mirror"), ([external], "extended")] {
        precondition(mode(layout) == expected)
        let values = preferences(layout)
        precondition(values["enableBrightnessSync"] as? Bool == (expected != "mirror"))
        for display in layout {
            precondition(values["isDisabled" + display.suffix!] as? Bool == (expected == "mirror" && display.builtIn))
        }
    }
    let unnamedLaptop = Screen(id: 1, builtIn: true, mirror: 2, mirrored: true, suffix: nil)
    let unnamedExternal = Screen(id: 2, builtIn: false, mirror: 0, mirrored: false, suffix: nil)
    precondition(mode([unnamedLaptop, external]) == "mirror")
    precondition(mode([laptop, unnamedExternal]) == "extended")
    precondition(preferences([unnamedLaptop, external])["isDisabled(External)"] as? Bool == false)
    precondition(signature([unnamedLaptop, external]) != signature([mirroredLaptop, external]))
    precondition(restoredBrightness(external: nil, saved: 0) == 0)
    precondition(restoredBrightness(external: nil, saved: 0.25) == 0.25)
    precondition(restoredBrightness(external: 0, saved: 0) == 0.05)
    precondition(runCommand("/usr/bin/true", []))
    precondition(!runCommand("/usr/bin/false", []))
    precondition(!runCommand("/nonexistent/monitorcontrol-test", []))
    print("Passed: display policies, missing names, zero restoration, and process failures")
}

switch CommandLine.arguments.dropFirst().first ?? "--status" {
case "--status": status()
case "--self-test": selfTest()
case "--once": exit(apply(screens()) ? 0 : 1)
case "--watch":
    var applied = ""
    var candidate = ""
    // Polling also catches wake/unlock events missed by display callbacks.
    // Wait for two matching observations before reacting to a new layout.
    let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        let displays = screens()
        guard !displays.isEmpty, displays.contains(where: { CGDisplayIsAsleep($0.id) == 0 }) else { return }
        let observed = signature(displays)
        if observed != candidate { candidate = observed; return }
        if observed != applied {
            if apply(displays) { applied = observed }
        } else if mode(displays) == "mirror" {
            // Keep ambient-light changes from lighting the laptop back up.
            for display in displays where display.builtIn {
                if let value = brightness(display.id), value > 0.001 {
                    _ = setBrightness(display.id, 0)
                }
            }
        }
    }
    withExtendedLifetime(timer) { RunLoop.current.run() }
default:
    fputs("Usage: monitorcontrol-mode [--status|--once|--watch|--self-test]\n", stderr)
    exit(2)
}
