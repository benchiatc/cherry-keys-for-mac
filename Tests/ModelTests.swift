import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}
private func check(
    _ condition: @autoclosure () throws -> Bool, _ message: String = "Assertion failed"
) throws {
    if try !condition() { throw TestFailure(description: message) }
}
private func rejects(_ description: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw TestFailure(description: "Expected rejection: \(description)")
}
private func mapping(
    _ code: Int = 122, kind: Trigger.Kind = .key, action: ActionKind = .disable, value: String = ""
) -> Assignment {
    var result = Assignment()
    result.trigger = Trigger(kind: kind, code: code)
    result.action = action
    result.value = value
    return result
}
private func configuration(_ assignments: [Assignment]) -> Configuration {
    var profile = Profile()
    profile.assignments = assignments
    return Configuration(profiles: [profile], selectedProfile: profile.id)
}
private func temporaryStore(_ body: (ConfigurationStore, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "CherryKeysModelTests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(
        ConfigurationStore(url: directory.appendingPathComponent("nested/configuration.json")),
        directory)
}

@main
struct ModelTests {
    static func main() {
        var passed = 0
        var failures: [String] = []
        func test(_ name: String, _ body: () throws -> Void) {
            do {
                try body()
                passed += 1
                print("PASS \(name)")
            } catch {
                failures.append("\(name): \(error)")
                print("FAIL \(name): \(error)")
            }
        }

        test("Missing file produces a valid default without writing") {
            try temporaryStore { store, _ in
                let config = try store.load()
                try config.validate()
                try check(config.profiles.count == 1)
                try check(!FileManager.default.fileExists(atPath: store.url.path))
            }
        }
        test("Unicode, multiline text, shortcut and macro round trip exactly") {
            try temporaryStore { store, _ in
                var text = mapping(122, action: .text, value: "你好 🍒 café e\u{301}\n日本語\t→ النهاية")
                text.modifiers = 0
                var macro = mapping(120, action: .macro)
                macro.steps = [
                    MacroStep(code: 0, down: true, flags: 1 << 20, delay: 0),
                    MacroStep(code: 0, down: false, flags: 1 << 20, delay: 0.125),
                    MacroStep(code: 36, down: true, flags: 0, delay: 0.05),
                    MacroStep(code: 36, down: false, flags: 0, delay: 0),
                ]
                var shortcut = mapping(99, action: .shortcut)
                shortcut.outputKey = 8
                shortcut.modifiers = (1 << 20) | (1 << 17)
                var config = configuration([text, macro, shortcut])
                var second = Profile()
                second.name = "Second profile 日本語"
                config.profiles.append(second)
                try store.save(config)
                let loaded = try store.load()
                try check(
                    loaded == config,
                    "Persistence changed Unicode, identifiers, flags, timing, or selection")
                try check(loaded.active.id == config.selectedProfile)
                let permissions =
                    try FileManager.default.attributesOfItem(atPath: store.url.path)[
                        .posixPermissions] as? NSNumber
                try check(
                    permissions?.intValue == 0o600,
                    "Configuration must have private 0600 permissions")
            }
        }
        test("Successful saves keep the exact immediately preceding bytes as backup") {
            try temporaryStore { store, _ in
                var config = configuration([mapping()])
                try store.save(config)
                let initial = try Data(contentsOf: store.url)
                let backup = store.url.appendingPathExtension("backup")
                try check(!FileManager.default.fileExists(atPath: backup.path))
                config.profiles[0].name = "Second version"
                try store.save(config)
                try check(try Data(contentsOf: backup) == initial)
                let backupPermissions =
                    try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions]
                    as? NSNumber
                try check(
                    backupPermissions?.intValue == 0o600,
                    "Backup must have private 0600 permissions")
                let second = try Data(contentsOf: store.url)
                config.profiles[0].name = "Third version"
                try store.save(config)
                try check(try Data(contentsOf: backup) == second)
                try check(try store.load() == config)
            }
        }
        test("Backup write failure leaves the original configuration intact") {
            try temporaryStore { store, _ in
                var config = configuration([mapping()])
                try store.save(config)
                let original = try Data(contentsOf: store.url)
                try FileManager.default.createDirectory(
                    at: store.url.appendingPathExtension("backup"),
                    withIntermediateDirectories: false)
                config.profiles[0].name = "Must not replace the original"
                try rejects("backup destination is a directory") { try store.save(config) }
                try check(try Data(contentsOf: store.url) == original)
                try check(try store.load().profiles[0].name != config.profiles[0].name)
            }
        }
        test("Corrupt JSON is rejected and its original bytes remain available") {
            try temporaryStore { store, _ in
                try FileManager.default.createDirectory(
                    at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let broken = Data("{\"profiles\": [broken 🍒".utf8)
                try broken.write(to: store.url)
                try rejects("corrupt JSON") { _ = try store.load() }
                try check(try Data(contentsOf: store.url) == broken)
                try check(
                    !FileManager.default.fileExists(
                        atPath: store.url.appendingPathExtension("backup").path))
            }
        }
        test("Invalid save preserves both current configuration and backup") {
            try temporaryStore { store, _ in
                var config = configuration([mapping()])
                try store.save(config)
                config.profiles[0].name = "Second"
                try store.save(config)
                let prior = try Data(contentsOf: store.url)
                let backup = try Data(contentsOf: store.url.appendingPathExtension("backup"))
                config.profiles = []
                try rejects("empty configuration") { try store.save(config) }
                try check(try Data(contentsOf: store.url) == prior)
                try check(
                    try Data(contentsOf: store.url.appendingPathExtension("backup")) == backup)
            }
        }
        test("Duplicate active triggers are rejected") {
            try rejects("two enabled mappings on F1") {
                try configuration([mapping(), mapping()]).validate()
            }
        }
        test("Inactive duplicates are permitted and survive persistence") {
            try temporaryStore { store, _ in
                var inactive = mapping()
                inactive.enabled = false
                let config = configuration([mapping(), inactive])
                try store.save(config)
                try check(try store.load() == config)
            }
        }
        test("Keyboard and media trigger namespaces are distinct") {
            try configuration([mapping(16), mapping(16, kind: .media)]).validate()
        }
        test("Separate profiles can assign the same trigger independently") {
            var config = configuration([mapping()])
            config.profiles.append(configuration([mapping()]).profiles[0])
            try config.validate()
        }
        test("Configuration structure rejects unsupported, empty and duplicate profiles") {
            var config = Configuration()
            config.version = 2
            try rejects("future version") { try config.validate() }
            config = Configuration()
            config.profiles = []
            try rejects("empty profiles") { try config.validate() }
            config = Configuration()
            config.profiles.append(config.profiles[0])
            try rejects("duplicate profile UUID") { try config.validate() }
            config = Configuration()
            config.profiles = (0..<101).map { _ in Profile() }
            try rejects("more than 100 profiles") { try config.validate() }
        }
        test("Invalid configuration read does not erase source file") {
            try temporaryStore { store, _ in
                try FileManager.default.createDirectory(
                    at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                var invalid = Configuration()
                invalid.version = 99
                let bytes = try JSONEncoder().encode(invalid)
                try bytes.write(to: store.url)
                try rejects("valid JSON with unsupported version") { _ = try store.load() }
                try check(try Data(contentsOf: store.url) == bytes)
            }
        }
        test("Websites require a nonempty HTTP or HTTPS hostname") {
            for valid in [
                "https://example.com/path?q=你好", "http://localhost:8080", "HTTPS://example.com",
            ] {
                try mapping(action: .website, value: valid).validate()
            }
            for invalid in [
                "", " \n ", "example.com", "file:///tmp/test", "javascript:alert(1)",
                "ftp://example.com", "https://", "http:///path",
            ] {
                try rejects("URL \(invalid)") {
                    try mapping(action: .website, value: invalid).validate()
                }
            }
        }
        test("File and application destinations must exist") {
            try temporaryStore { _, directory in
                let file = directory.appendingPathComponent("sample.txt")
                try Data("test".utf8).write(to: file)
                try mapping(action: .file, value: file.path).validate()
                try mapping(action: .application, value: directory.path).validate()
                try rejects("missing destination") {
                    try mapping(action: .file, value: file.path + ".missing").validate()
                }
                try rejects("empty application") {
                    try mapping(action: .application, value: " ").validate()
                }
            }
        }
        test("Empty text, invalid output key and unsupported media actions are rejected") {
            try rejects("whitespace text") { try mapping(action: .text, value: " \n\t").validate() }
            var shortcut = mapping(action: .shortcut)
            shortcut.outputKey = 128
            try rejects("shortcut outside CG key range") { try shortcut.validate() }
            shortcut.outputKey = -1
            try rejects("negative shortcut") { try shortcut.validate() }
            var media = mapping(action: .media)
            media.mediaCode = 255
            try rejects("unknown output media code") { try media.validate() }
        }
        test("Macro validation rejects invalid timing, keys, excessive events and duration") {
            var macro = mapping(action: .macro)
            try rejects("empty recording") { try macro.validate() }
            for delay in [-0.01, 30.01, Double.infinity, Double.nan] {
                macro.steps = [MacroStep(code: 0, down: true, flags: 0, delay: delay)]
                try rejects("invalid event delay \(delay)") { try macro.validate() }
            }
            for code in [-1, 128, Int.max] {
                macro.steps = [MacroStep(code: code, down: true, flags: 0, delay: 0)]
                try rejects("invalid macro key \(code)") { try macro.validate() }
            }
            macro.steps = Array(
                repeating: MacroStep(code: 0, down: true, flags: 0, delay: 0), count: 4001)
            try rejects("too many events") { try macro.validate() }
            macro.steps = Array(
                repeating: MacroStep(code: 0, down: true, flags: 0, delay: 30), count: 11)
            try rejects("over five minutes") { try macro.validate() }
            macro.steps = Array(
                repeating: MacroStep(code: 0, down: true, flags: 0, delay: 30), count: 10)
            try macro.validate()
        }
        test("Trigger values must belong to their input namespace") {
            for code in [-1, 128, 255, 256] {
                try rejects("invalid keyboard trigger \(code)") { try mapping(code).validate() }
            }
            for code in [-1, 256] {
                try rejects("unsupported media trigger \(code)") {
                    try mapping(code, kind: .media).validate()
                }
            }
        }
        test("Consumer triggers are allowlisted and persist independently of function keys") {
            try temporaryStore { store, _ in
                let assignments =
                    ConsumerControl.allCases.map { $0.defaultAssignment }
                    + [mapping(100), mapping(103), mapping(111)]
                let config = configuration(assignments)
                try store.save(config)
                try check(try store.load() == config)
                for control in ConsumerControl.allCases {
                    try check(!control.title.isEmpty)
                }
                for code in [-1, 0, 16, 0x224, 0xffff, Int.max] {
                    try rejects("unknown consumer control") {
                        try mapping(code, kind: .consumer).validate()
                    }
                }
            }
        }
        test("Trigger labels distinguish preset functions from standard Fn keys") {
            try check(Trigger(kind: .key, code: 111).title == "Fn + F12 — standard F12")
            try check(Trigger(kind: .consumer, code: 0x18a).title == "F12 — Mail (preset)")
            try check(Trigger(kind: .key, code: 100).title.contains("Fn + F8"))
            try check(Trigger(kind: .consumer, code: 0x223).title.contains("preset"))
            try check(Trigger(kind: .key, code: 55).title == "Left Command")
            try check(
                KeyCatalog.name(111) == "F12", "Output key names must stay independent of Fn labels"
            )
        }
        test("Assignments require unique stable identifiers within a profile") {
            var first = mapping(122)
            first.id = UUID()
            var second = first
            second.trigger.code = 120
            try rejects("duplicate assignment identifier") {
                try configuration([first, second]).validate()
            }
        }

        test("Modifier mappings and every Mac action round trip without changing existing profiles")
        {
            try temporaryStore { store, _ in
                var config = Configuration()
                for (source, destination) in [(55, 58), (58, 55), (54, 61), (61, 54)] {
                    var a = mapping(source, action: .modifier)
                    a.outputKey = destination
                    config.profiles[0].assignments.append(a)
                }
                for action in MacAction.allCases {
                    var profile = Profile()
                    profile.name = action.title
                    profile.assignments = [mapping(122, action: .macAction, value: action.rawValue)]
                    config.profiles.append(profile)
                }
                try store.save(config)
                try check(try store.load() == config)
            }
        }
        test("Modifier destinations and Mac action identifiers are validated") {
            var a = mapping(58, action: .modifier)
            a.outputKey = 55
            try a.validate()
            a.outputKey = 0
            try rejects("ordinary key as modifier output") { try a.validate() }
            a.trigger.code = 122
            a.outputKey = 55
            try rejects("ordinary trigger for modifier output") { try a.validate() }
            try rejects("text action on a held modifier") {
                try mapping(58, action: .text, value: "text").validate()
            }
            try mapping(58, action: .disable).validate()
            try rejects("unknown Mac action") {
                try mapping(action: .macAction, value: "not-an-action").validate()
            }
            try rejects("empty Mac action") { try mapping(action: .macAction).validate() }
        }

        test("Oversized profiles and disabled payloads are rejected") {
            var a = mapping(action: .text, value: String(repeating: "x", count: 65537))
            a.enabled = false
            try rejects("disabled oversized text") { try configuration([a]).validate() }
            var p = Profile()
            p.name = String(repeating: "x", count: 257)
            try rejects("oversized profile name") { try p.validate() }
            p.name = "Test"
            p.assignments = (0..<1001).map { _ in mapping() }
            try rejects("too many assignments") { try p.validate() }
        }
        test("Oversized JSON input is rejected without changing it") {
            try temporaryStore { store, directory in
                let file = directory.appendingPathComponent("oversized.json")
                let data = Data(repeating: 32, count: ConfigurationStore.maximumBytes + 1)
                try data.write(to: file)
                try rejects("oversized input") { _ = try ConfigurationStore.read(file) }
                try check(try Data(contentsOf: file) == data)
            }
        }
        print("\n\(passed) passed; \(failures.count) failed")
        if !failures.isEmpty {
            for failure in failures { fputs("\(failure)\n", stderr) }
            exit(1)
        }
    }
}
