// Keep BetterDisplay's brightness policy in step with the display layout.
// BetterDisplay reads per-display preferences only at launch, so the app is
// restarted only when a managed preference actually has to change.
import AppKit
import CoreGraphics
import Foundation

@_silgen_name("DisplayServicesGetBrightness")
func getBrightness(_ display: CGDirectDisplayID, _ value: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
func setBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Int32
@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func displayInfo(_ display: CGDirectDisplayID) -> Unmanaged<CFDictionary>?

let domain = "pro.betterdisplay.BetterDisplay"
let appPath = "/Applications/BetterDisplay.app"
let cliPath = appPath + "/Contents/MacOS/BetterDisplay"
let state = UserDefaults(suiteName: "local.dotfiles.betterdisplay-mode")!

struct Screen {
    let id: CGDirectDisplayID
    let builtIn: Bool
    let virtual: Bool
    /// The display whose content this one shows; itself when not mirroring.
    let root: CGDirectDisplayID
}

/// A display as BetterDisplay numbers it in its preference keys (`…@Display:<number>`).
struct Tag {
    let number: Int
    let displayID: CGDirectDisplayID?
    let builtIn: Bool
    let virtual: Bool
    let connected: Bool
}

/// Virtual screens (BetterDisplay's own, Sidecar-like devices) never count as monitors.
func isVirtual(_ id: CGDirectDisplayID) -> Bool {
    guard let info = displayInfo(id)?.takeRetainedValue() as? [String: Any] else { return false }
    return (info["kCGDisplayIsVirtualDevice"] as? NSNumber)?.boolValue ?? false
}

func screens() -> [Screen] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map { id in
        let mirror = CGDisplayMirrorsDisplay(id)
        return Screen(id: id, builtIn: CGDisplayIsBuiltin(id) != 0, virtual: isVirtual(id),
                      root: mirror != 0 ? mirror : id)
    }
}

/// Mirroring means the built-in panel shows the same image as a physical monitor.
/// Mirroring a virtual screen alone (screen sharing setups) is not "mirror".
func mode(_ displays: [Screen]) -> String {
    let physical = displays.filter { !$0.virtual }
    let externalRoots = Set(physical.filter { !$0.builtIn }.map(\.root))
    guard !externalRoots.isEmpty else { return "laptop" }
    return physical.contains { $0.builtIn && externalRoots.contains($0.root) } ? "mirror" : "extended"
}

/// Reads one value from BetterDisplay's preference domain.
func readPref(_ key: String) -> Any? {
    CFPreferencesCopyAppValue(key as CFString, domain as CFString)
}

/// Updates one key without replacing unrelated application preferences.
func writePref(_ key: String, _ value: Any) {
    CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain as CFString)
}

func flag(_ key: String) -> Bool {
    (readPref(key) as? NSNumber)?.boolValue ?? false
}

/// Lists the displays BetterDisplay has recorded, including offline ones.
func tags() -> [Tag] {
    CFPreferencesAppSynchronize(domain as CFString)
    guard let raw = readPref("displayTagIDs") as? String,
          let numbers = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [Int] else { return [] }
    return numbers.map { number in
        let key = "@Display:\(number)"
        // BetterDisplay stores this ID as a string.
        let persisted = readPref("persistedDisplayID" + key)
        return Tag(number: number,
                   displayID: (persisted as? NSNumber)?.uint32Value ?? (persisted as? String).flatMap { UInt32($0) },
                   builtIn: flag("builtIn" + key),
                   virtual: flag("systemVirtual" + key) || flag("thirdPartyVirtual" + key),
                   connected: flag("connected" + key))
    }
}

/// Builds the managed settings. Display-specific keys exist only for displays
/// BetterDisplay has already seen, so they are filled in once it records them.
func preferences(_ mode: String, _ known: [Tag]) -> [String: Any] {
    let mirror = mode == "mirror"
    var values: [String: Any] = [
        // Brightness keys adjust every display with brightness control.
        "videoKeyboardControl": "all",
        // Volume keys drive a monitor over DDC only while it is the default
        // output; otherwise they are left to macOS.
        "audioKeyboardControl": "displayWithAudioDeviceNameMatch",
    ]
    for tag in known where !tag.virtual {
        if tag.builtIn {
            // While mirroring, keep the blanked laptop panel out of key presses.
            values["allowKeyboardControl@Display:\(tag.number)"] = !mirror
        } else {
            // Software dimming can darken the mirrored image. Use DDC only.
            values["allowCombinedBrightness@Display:\(tag.number)"] = !mirror
        }
    }
    return values
}

/// Compares preference values across Bool/NSNumber bridging.
func matches(_ current: Any?, _ wanted: Any) -> Bool {
    guard let current = current as? NSObject else { return false }
    return current.isEqual(wanted)
}

/// Reads physical Apple-panel brightness, returning nil for unsupported displays.
func brightness(_ id: CGDirectDisplayID) -> Float? {
    var value: Float = 0
    return getBrightness(id, &value) == 0 ? value : nil
}

/// Launches an executable and returns its standard output, or nil on failure.
func runCommand(_ executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        fputs("Could not launch \(executable): \(error)\n", stderr)
        return nil
    }
}

/// Returns false when Launch Services cannot reopen BetterDisplay, allowing retries.
@discardableResult
func openBetterDisplay() -> Bool {
    runCommand("/usr/bin/open", ["-g", "-a", appPath]) != nil
}

func runningApps() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: domain)
}

/// Restores an exact saved zero; the visibility floor applies only to external sync.
func restoredBrightness(external: Float?, saved: Float) -> Float {
    if let external = external { return max(0.05, min(1, external)) }
    return max(0, min(1, saved))
}

/// Applies a stable topology. BetterDisplay is stopped only while managed
/// preferences change, so virtual screens and mirroring stay untouched otherwise.
func apply(_ displays: [Screen]) -> Bool {
    guard !displays.isEmpty else { return false }
    let currentMode = mode(displays)
    let known = tags()
    let wanted = preferences(currentMode, known)
    let changed = wanted.contains { !matches(readPref($0.key), $0.value) }
    if changed {
        let apps = runningApps()
        for app in apps { _ = app.terminate() }
        let deadline = Date().addingTimeInterval(4)
        while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard apps.allSatisfy({ $0.isTerminated }) else {
            fputs("BetterDisplay did not quit; will retry without overwriting its preferences.\n", stderr)
            return false
        }
        guard signature(screens()) == signature(displays) else {
            openBetterDisplay()
            return false
        }
    }
    CFPreferencesAppSynchronize(domain as CFString)
    // Keep this flag while the lid is closed, so reopening the laptop after
    // unplugging its monitor still restores a backlight we previously blanked.
    let wasBlanked = state.object(forKey: "builtInBlanked") as? Bool
        ?? (state.string(forKey: "mode") == "mirror")
    let onlineIDs = Set(displays.map(\.id))
    let externalTag = known.first { !$0.builtIn && !$0.virtual && $0.displayID.map(onlineIDs.contains) == true }
    for display in displays where display.builtIn {
        if currentMode == "mirror" {
            if !wasBlanked, let value = brightness(display.id) {
                state.set(value, forKey: "builtInBrightness")
            }
        } else if currentMode == "extended" || wasBlanked {
            let externalValue = externalTag.flatMap {
                readPref("value@hardwareBrightness-DDCController@Display:\($0.number)") as? NSNumber
            }?.floatValue
            let saved = (!wasBlanked ? brightness(display.id) : nil)
                ?? (state.object(forKey: "builtInBrightness") as? NSNumber)?.floatValue ?? 0.5
            let target = restoredBrightness(external: externalValue, saved: saved)
            guard setBrightness(display.id, target) == 0 else {
                if changed { openBetterDisplay() }
                return false
            }
            state.set(false, forKey: "builtInBlanked")
        }
    }
    if changed {
        for (key, value) in wanted { writePref(key, value) }
        guard CFPreferencesAppSynchronize(domain as CFString) else {
            openBetterDisplay()
            return false
        }
    }
    // Exclude the panel from brightness keys before blanking it, so a key
    // press never lights the laptop back up.
    if currentMode == "mirror" {
        guard signature(screens()) == signature(displays) else {
            if changed { openBetterDisplay() }
            return false
        }
        for display in displays where display.builtIn {
            state.set(true, forKey: "builtInBlanked")
            state.synchronize()
            guard setBrightness(display.id, 0) == 0 else {
                if changed { openBetterDisplay() }
                return false
            }
        }
    }
    state.set(currentMode, forKey: "mode")
    state.synchronize()
    if changed || runningApps().isEmpty {
        guard openBetterDisplay() else { return false }
    }
    print("Applied \(currentMode) brightness policy\(changed ? " (BetterDisplay restarted)" : "")")
    fflush(stdout)
    return true
}

/// Physical displays only: creating or connecting a virtual screen is not a
/// layout change, but mirroring a monitor to one is. Built-in tag availability
/// is included so a newly recorded laptop panel triggers reapplication.
func signature(_ displays: [Screen]) -> String {
    let builtInTagKnown = tags().contains { $0.builtIn }
    return displays.filter { !$0.virtual }
        .map { "\($0.id):\($0.builtIn):\($0.root)" + ($0.builtIn ? ":\(builtInTagKnown)" : "") }
        .sorted().joined(separator: ";")
}

/// Copies the monitor's current DDC brightness and volume into BetterDisplay
/// once, so the first key press continues from the real level instead of
/// BetterDisplay's default of 100%.
func seedDDC() -> Bool {
    let pending = tags().filter { tag in
        tag.connected && !tag.builtIn && !tag.virtual
            && ["hardwareBrightness", "hardwareVolume"].contains {
                readPref("value@\($0)-DDCController@Display:\(tag.number)") == nil
            }
    }
    guard !pending.isEmpty else { return true }
    // BetterDisplay may have just been (re)started; its CLI answers once ready.
    let deadline = Date().addingTimeInterval(20)
    while runCommand(cliPath, ["get", "-proAvailable"]) == nil {
        guard Date() < deadline else { return false }
        Thread.sleep(forTimeInterval: 1)
    }
    var ok = true
    for tag in pending {
        for (vcp, feature, stored) in [("luminance", "hardwareBrightness", "hardwareBrightness"),
                                      ("audioSpeakerVolume", "volume", "hardwareVolume")] {
            guard readPref("value@\(stored)-DDCController@Display:\(tag.number)") == nil else { continue }
            let target = "-tagID=\(tag.number)"
            guard let current = runCommand(cliPath, ["get", target, "-ddc", "-vcp=\(vcp)"]).flatMap(Double.init),
                  let maximum = runCommand(cliPath, ["get", target, "-ddc", "-vcp=\(vcp)", "-max"]).flatMap(Double.init),
                  maximum > 0 else {
                print("Display \(tag.number): \(vcp) is not readable over DDC; leaving BetterDisplay's value")
                continue
            }
            let value = max(0, min(1, current / maximum))
            if runCommand(cliPath, ["set", target, "-\(feature)=\(value)"]) == nil {
                ok = false
            } else {
                print("Display \(tag.number): seeded \(feature)=\(value) from DDC")
            }
        }
    }
    return ok
}

/// Prints the detected topology, panel brightness, and effective managed settings.
func status() {
    let displays = screens()
    let known = tags()
    print("mode=\(mode(displays))")
    for display in displays {
        let tag = known.first { $0.displayID == display.id }
        print("display \(display.id) tag=\(tag.map { String($0.number) } ?? "unknown") builtIn=\(display.builtIn) virtual=\(display.virtual) mirrors=\(display.root == display.id ? "none" : String(display.root)) brightness=\(brightness(display.id).map(String.init(describing:)) ?? "DDC")")
    }
    for (key, value) in preferences(mode(displays), known).sorted(by: { $0.key < $1.key }) {
        print("\(key)=\(readPref(key).map(String.init(describing:)) ?? "unset") (wanted \(value))")
    }
}

/// Exercises topology decisions, managed preferences, zero restoration, and subprocess handling.
func selfTest() {
    let laptop = Screen(id: 1, builtIn: true, virtual: false, root: 1)
    let mirroredLaptop = Screen(id: 1, builtIn: true, virtual: false, root: 2)
    let external = Screen(id: 2, builtIn: false, virtual: false, root: 2)
    let share = Screen(id: 3, builtIn: false, virtual: true, root: 3)
    let externalOnShare = Screen(id: 2, builtIn: false, virtual: false, root: 3)
    let laptopOnShare = Screen(id: 1, builtIn: true, virtual: false, root: 3)
    for (layout, expected) in [([laptop], "laptop"), ([laptop, external], "extended"),
                               ([mirroredLaptop, external], "mirror"), ([external], "extended"),
                               // Desktop Mac sharing a virtual 16:9 screen.
                               ([share, externalOnShare], "extended"),
                               // Laptop mirroring only a virtual screen keeps its panel.
                               ([laptopOnShare, share], "laptop"),
                               ([laptopOnShare, share, external], "extended"),
                               // Panel and monitor both show the virtual screen.
                               ([laptopOnShare, share, externalOnShare], "mirror")] {
        precondition(mode(layout) == expected, "\(layout) should be \(expected)")
    }
    let known = [Tag(number: 1, displayID: 1, builtIn: true, virtual: false, connected: true),
                 Tag(number: 2, displayID: 2, builtIn: false, virtual: false, connected: true),
                 Tag(number: 4, displayID: 3, builtIn: false, virtual: true, connected: true)]
    for current in ["laptop", "extended", "mirror"] {
        let values = preferences(current, known)
        precondition(values["videoKeyboardControl"] as? String == "all")
        precondition(values["audioKeyboardControl"] as? String == "displayWithAudioDeviceNameMatch")
        precondition(values["allowKeyboardControl@Display:1"] as? Bool == (current != "mirror"))
        precondition(values["allowCombinedBrightness@Display:2"] as? Bool == (current != "mirror"))
        precondition(values.keys.allSatisfy { !$0.hasSuffix("@Display:4") }, "virtual screens are unmanaged")
    }
    precondition(preferences("mirror", []).count == 2)
    precondition(matches(NSNumber(value: 1), true) && matches(NSNumber(value: false), false))
    precondition(!matches(nil, true) && !matches("all" as NSString, "displayWithMouse"))
    precondition(restoredBrightness(external: nil, saved: 0) == 0)
    precondition(restoredBrightness(external: nil, saved: 0.25) == 0.25)
    precondition(restoredBrightness(external: 0, saved: 0) == 0.05)
    precondition(runCommand("/bin/echo", ["ok"]) == "ok")
    precondition(runCommand("/usr/bin/false", []) == nil)
    precondition(runCommand("/nonexistent/betterdisplay-test", []) == nil)
    print("Passed: display policies, virtual screens, managed settings, zero restoration, and process failures")
}

switch CommandLine.arguments.dropFirst().first ?? "--status" {
case "--status": status()
case "--self-test": selfTest()
case "--once": exit(apply(screens()) ? 0 : 1)
case "--seed-ddc": exit(seedDDC() ? 0 : 1)
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
            if apply(displays) {
                applied = observed
                // A newly connected monitor starts from its real DDC levels.
                if !seedDDC() { fputs("Could not seed every DDC value.\n", stderr) }
            }
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
    fputs("Usage: betterdisplay-mode [--status|--once|--watch|--seed-ddc|--self-test]\n", stderr)
    exit(2)
}
