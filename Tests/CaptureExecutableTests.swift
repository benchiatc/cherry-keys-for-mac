import Foundation

@main
struct CaptureExecutableTests {
    static func main() throws {
        let source = CommandLine.arguments[1]
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let candidate = temporary.appendingPathComponent("candidate")
        try FileManager.default.copyItem(atPath: source, toPath: candidate.path)
        var snapshot: CaptureExecutable? = try CaptureExecutable(source: candidate.path)
        let snapshotURL = snapshot!.url
        let bytes = try Data(contentsOf: snapshotURL)
        // A replacement after validation cannot change the executable snapshot.
        try Data("replaced".utf8).write(to: candidate, options: .atomic)
        let retained = try Data(contentsOf: snapshotURL)
        precondition(retained == bytes)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: snapshot!.directory.path)
        precondition((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        snapshot = nil
        precondition(!FileManager.default.fileExists(atPath: snapshotURL.path))
        do {
            _ = try CaptureExecutable(source: candidate.path)
            preconditionFailure("Unsigned replacement must be rejected")
        } catch {}
        let link = temporary.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: source))
        do {
            _ = try CaptureExecutable(source: link.path)
            preconditionFailure("Symlink must be rejected")
        } catch {}
        print(
            "PASS: executable snapshot survives source replacement, has private permissions, cleans up, rejects unsigned data and symlinks. No executable launched or hardware opened."
        )
    }
}
