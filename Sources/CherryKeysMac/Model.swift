import Foundation

struct Trigger: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case key, media, consumer }
    var kind: Kind = .key
    var code: Int = 122
    var title: String {
        switch kind {
        case .key: return KeyCatalog.name(code)
        case .media: return KeyCatalog.media[code] ?? "Media \(code)"
        case .consumer: return ConsumerControl(rawValue: code)?.title ?? "Consumer \(code)"
        }
    }
}
enum ActionKind: String, Codable, CaseIterable {
    case modifier, macAction, shortcut, text, macro, application, file, website, media, browserBack,
        browserForward, defaultMail, disable, lock, sleep
    var title: String {
        switch self {
        case .modifier: return "Modifier key"
        case .macAction: return "Mac action"
        case .shortcut: return "Keyboard shortcut"
        case .text: return "Insert text"
        case .macro: return "Recorded macro"
        case .application: return "Launch application"
        case .file: return "Open file or folder"
        case .website: return "Open website"
        case .media: return "Media control"
        case .browserBack: return "Browser back"
        case .browserForward: return "Browser forward"
        case .defaultMail: return "Open default mail app"
        case .disable: return "Disable key"
        case .lock: return "Lock screen"
        case .sleep: return "Sleep Mac"
        }
    }
}
struct MacroStep: Codable, Equatable {
    var code: Int
    var down: Bool
    var flags: UInt64
    var delay: Double
}
struct Assignment: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger = Trigger()
    var action: ActionKind = .shortcut
    var value = ""
    var outputKey = 0
    var modifiers: UInt64 = 1 << 20  // command
    var mediaCode = 16
    var steps: [MacroStep] = []
    var enabled = true
    var summary: String {
        switch action {
        case .modifier: return KeyCatalog.name(outputKey)
        case .macAction: return MacAction(rawValue: value)?.title ?? "Choose Mac action"
        case .shortcut: return KeyCatalog.modifierLabel(modifiers) + KeyCatalog.name(outputKey)
        case .text: return String(value.prefix(45)).replacingOccurrences(of: "\n", with: " ↵ ")
        case .macro: return "\(steps.count) recorded events"
        case .media: return KeyCatalog.media[mediaCode] ?? "Media"
        default: return value.isEmpty ? action.title : value
        }
    }
    func validate() throws {
        guard value.utf8.count <= 65536, steps.count <= 4000 else {
            throw AppError.message("Assignment exceeds size limits.")
        }
        let validTrigger: Bool
        switch trigger.kind {
        case .key: validTrigger = (0...127).contains(trigger.code)
        case .media: validTrigger = (0...255).contains(trigger.code)
        case .consumer: validTrigger = ConsumerControl(rawValue: trigger.code) != nil
        }
        if !validTrigger {
            throw AppError.message("Invalid trigger key.")
        }
        if trigger.kind == .key && [57, 63].contains(trigger.code) {
            throw AppError.message("Caps Lock and hardware Fn triggers are not supported.")
        }
        if trigger.kind == .key && KeyCatalog.modifierKeys.contains(trigger.code)
            && ![ActionKind.modifier, .disable].contains(action)
        {
            throw AppError.message("Choose Modifier key or Disable key for a modifier trigger.")
        }
        if action == .modifier
            && (!KeyCatalog.modifierKeys.contains(trigger.code) || trigger.kind != .key
                || !KeyCatalog.modifierKeys.contains(outputKey))
        {
            throw AppError.message("Choose a modifier trigger and modifier destination.")
        }
        if action == .macAction && MacAction(rawValue: value) == nil {
            throw AppError.message("Choose a Mac action.")
        }
        if [.application, .file, .website, .text].contains(action)
            && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw AppError.message("Enter a value for this action.")
        }
        if [.application, .file].contains(action) && !FileManager.default.fileExists(atPath: value)
        {
            throw AppError.message("The selected file or application no longer exists.")
        }
        if action == .website {
            guard let url = URL(string: value),
                ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
            else { throw AppError.message("Enter a complete http:// or https:// website address.") }
        }
        if action == .macro {
            guard !steps.isEmpty, steps.count <= 4000 else {
                throw AppError.message("Record a macro with 1–4000 events.")
            }
            guard
                steps.allSatisfy({
                    $0.code >= 0 && $0.code < 128 && $0.delay.isFinite && $0.delay >= 0
                        && $0.delay <= 30
                }), steps.reduce(0, { $0 + $1.delay }) <= 300
            else {
                throw AppError.message(
                    "Macro timing or keys are invalid; maximum duration is five minutes.")
            }
        }
        if action == .shortcut && !(0..<128).contains(outputKey) {
            throw AppError.message("Invalid output key.")
        }
        if action == .media && KeyCatalog.media[mediaCode] == nil {
            throw AppError.message("Invalid media action.")
        }
    }
}

/// USB HID Consumer-page controls, kept separate from Quartz keys and NX media codes.
/// An explicit allowlist prevents arbitrary usages from becoming launch actions.
enum ConsumerControl: Int, CaseIterable {
    case browserHome = 0x223
    case calculator = 0x192
    case mail = 0x18a

    var title: String {
        switch self {
        case .browserHome: return "Browser Home (F8 alternate)"
        case .calculator: return "Calculator (F11 alternate)"
        case .mail: return "Mail (F12 alternate)"
        }
    }
    var defaultAssignment: Assignment {
        var assignment = Assignment()
        assignment.trigger = Trigger(kind: .consumer, code: rawValue)
        switch self {
        case .browserHome:
            // Safari/Chrome's Home shortcut; the foreground app handles it.
            assignment.action = .shortcut
            assignment.outputKey = 4
            assignment.modifiers = (1 << 20) | (1 << 17)
        case .calculator:
            assignment.action = .application
            assignment.value = "/System/Applications/Calculator.app"
        case .mail:
            assignment.action = .defaultMail
        }
        return assignment
    }
}
struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "My KW X ULP"
    var assignments: [Assignment] = []
    func validate() throws {
        guard name.utf8.count <= 256, assignments.count <= 1000 else {
            throw AppError.message("Profile exceeds size limits.")
        }
        guard assignments.allSatisfy({ $0.value.utf8.count <= 65536 && $0.steps.count <= 4000 })
        else { throw AppError.message("Assignment exceeds size limits.") }
        guard Set(assignments.map(\.id)).count == assignments.count else {
            throw AppError.message("Duplicate assignment identifiers.")
        }
        var seen = Set<Trigger>()
        for a in assignments where a.enabled {
            try a.validate()
            guard seen.insert(a.trigger).inserted else {
                throw AppError.message("\(a.trigger.title) has more than one enabled assignment.")
            }
        }
    }
}
struct Configuration: Codable, Equatable {
    var version = 1
    var profiles: [Profile] = [Profile()]
    var selectedProfile: UUID?
    var active: Profile { profiles.first(where: { $0.id == selectedProfile }) ?? profiles[0] }
    func validate() throws {
        guard version == 1, !profiles.isEmpty, profiles.count <= 100 else {
            throw AppError.message("Unsupported or empty configuration.")
        }
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw AppError.message("Duplicate profile identifiers.")
        }
        for p in profiles { try p.validate() }
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}
struct ConfigurationStore {
    let url: URL
    init(
        url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
            0
        ].appendingPathComponent("CherryKeysMac/configuration.json")
    ) { self.url = url }
    static let maximumBytes = 4 * 1024 * 1024
    private static func boundedData(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            throw AppError.message("Configuration exceeds 4 MiB.")
        }
        return data
    }
    static func read(_ url: URL) throws -> Configuration {
        let config = try JSONDecoder().decode(Configuration.self, from: boundedData(url))
        try config.validate()
        return config
    }
    func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        return try Self.read(url)
    }
    func save(_ config: Configuration) throws {
        try config.validate()
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        guard data.count <= Self.maximumBytes else {
            throw AppError.message("Configuration exceeds 4 MiB.")
        }
        if fm.fileExists(atPath: url.path) {
            let prior = try Self.boundedData(url)
            try prior.write(to: url.appendingPathExtension("backup"), options: .atomic)
            try fm.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.appendingPathExtension("backup").path)
        }
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
enum KeyCatalog {
    static let media = [
        0: "Volume up", 1: "Volume down", 2: "Brightness up", 3: "Brightness down", 7: "Mute",
        16: "Play / pause", 17: "Next track", 18: "Previous track",
    ]
    static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Escape", 55: "Left Command", 54: "Right Command",
        56: "Left Shift", 57: "Caps Lock", 58: "Left Option", 59: "Left Control", 60: "Right Shift",
        61: "Right Option", 62: "Right Control", 63: "Fn", 64: "F17", 65: "Keypad .",
        67: "Keypad *", 69: "Keypad +", 71: "Keypad Clear", 75: "Keypad /", 76: "Keypad Enter",
        78: "Keypad −", 79: "F18", 80: "F19", 81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1",
        84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6",
        89: "Keypad 7", 90: "F20", 91: "Keypad 8", 92: "Keypad 9", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13 / Print Screen", 106: "F16",
        107: "F14 / Scroll Lock", 109: "F10", 111: "F12", 113: "F15 / Pause", 114: "Help / Insert",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow",
        126: "Up Arrow",
    ]
    static let modifierKeys = [59, 56, 58, 55, 62, 60, 61, 54]
    static let functionKeys = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]
    static func name(_ code: Int) -> String { names[code] ?? "Key \(code)" }
    static func modifierLabel(_ flags: UInt64) -> String {
        [
            (UInt64(1 << 18), "⌃"), (UInt64(1 << 19), "⌥"), (UInt64(1 << 17), "⇧"),
            (UInt64(1 << 20), "⌘"),
        ].filter { flags & $0.0 != 0 }.map(\.1).joined()
    }
}

/// Wait only for the approved service to connect. No password prompt is launched.
/// Secure input after connection restores native keyboard handling.
enum CaptureGate {
    enum Decision: Equatable {
        case awaitHelper, heartbeat, stopSecureEntry, stopPermissionLoss, stopHelperTimeout
    }
    static func decide(connected: Bool, secureInput: Bool, canPost: Bool, elapsed: Double)
        -> Decision
    {
        guard canPost else { return .stopPermissionLoss }
        guard connected else { return elapsed > 10 ? .stopHelperTimeout : .awaitHelper }
        return secureInput ? .stopSecureEntry : .heartbeat
    }
}

// Standard macOS shortcuts; users can customize the corresponding system shortcuts.
enum MacAction: String, CaseIterable {
    case spotlight, emoji, screenshot, screenshotSelection, screenshotTools, forceQuit, hideApp,
        hideOthers, minimize, closeWindow, newTab, nextTab, previousTab, pastePlain, undo, redo,
        find, selectAll
    var title: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .emoji: return "Emoji & Symbols"
        case .screenshot: return "Screenshot: entire screen"
        case .screenshotSelection: return "Screenshot: selection"
        case .screenshotTools: return "Screenshot & recording tools"
        case .forceQuit: return "Force Quit window"
        case .hideApp: return "Hide current app"
        case .hideOthers: return "Hide other apps"
        case .minimize: return "Minimize window"
        case .closeWindow: return "Close window"
        case .newTab: return "New tab"
        case .nextTab: return "Next tab"
        case .previousTab: return "Previous tab"
        case .pastePlain: return "Paste and match style"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .find: return "Find"
        case .selectAll: return "Select all"
        }
    }
    var shortcut: (Int, UInt64) {
        let cmd: UInt64 = 1 << 20
        let shift: UInt64 = 1 << 17
        let option: UInt64 = 1 << 19
        let control: UInt64 = 1 << 18
        switch self {
        case .spotlight: return (49, cmd)
        case .emoji: return (49, control | cmd)
        case .screenshot: return (20, cmd | shift)
        case .screenshotSelection: return (21, cmd | shift)
        case .screenshotTools: return (23, cmd | shift)
        case .forceQuit: return (53, cmd | option)
        case .hideApp: return (4, cmd)
        case .hideOthers: return (4, cmd | option)
        case .minimize: return (46, cmd)
        case .closeWindow: return (13, cmd)
        case .newTab: return (17, cmd)
        case .nextTab: return (48, control)
        case .previousTab: return (48, control | shift)
        case .pastePlain: return (9, cmd | option | shift)
        case .undo: return (6, cmd)
        case .redo: return (6, cmd | shift)
        case .find: return (3, cmd)
        case .selectAll: return (0, cmd)
        }
    }
}
