import Foundation
import Security

@main
struct CaptureServiceTests {
    static var checks = 0
    static func check(_ value: Bool, _ message: String) {
        precondition(value, message)
        checks += 1
    }
    static func valid(_ path: String, _ requirement: String) -> Bool {
        var code: SecStaticCode?
        var parsed: SecRequirement?
        guard
            SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code)
                == errSecSuccess,
            SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess,
            let code, let parsed
        else { return false }
        return SecStaticCodeCheckValidity(
            code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), parsed)
            == errSecSuccess
    }
    static func main() throws {
        let root = CommandLine.arguments[1]
        let app = root + "/.build/package.noindex/Cherry Keys for Mac.app"
        let good = "/private/tmp/ckm-" + UUID().uuidString
        check(
            CaptureServiceInfo.validSocketDirectory(good),
            "A fresh private capture directory is accepted")
        for bad in [
            "/tmp/ckm-" + UUID().uuidString, good + "/../other", good + "/",
            "/private/tmp/ckm-nope", "/", good + "\0", "/private/tmp/ckm-../../file",
        ] {
            check(
                !CaptureServiceInfo.validSocketDirectory(bad),
                "Only an exact private UUID directory is accepted")
        }
        let guiRequirement = try CaptureServiceInfo.requirement(identifier: "local.cherrykeys.mac")
        check(
            guiRequirement.contains("certificate leaf"),
            "Authentication pins a real signing certificate")
        check(valid(app, guiRequirement), "The intact app signed with our certificate is accepted")
        check(
            !valid(app, try CaptureServiceInfo.requirement(identifier: "local.cherrykeys.other")),
            "Same signer with another identifier is rejected")
        check(
            !valid(
                app,
                "identifier \"local.cherrykeys.mac\" and certificate leaf = H\"0000000000000000000000000000000000000000\""
            ), "Same identifier with another signer is rejected")
        check(
            valid(
                app + "/Contents/MacOS/CherryKeysCaptureService",
                try CaptureServiceInfo.requirement(identifier: CaptureServiceInfo.name)),
            "The managed broker has the pinned identity")
        check(
            valid(
                app + "/Contents/MacOS/CherryKeysHIDCapture",
                try CaptureServiceInfo.requirement(identifier: "local.cherrykeys.mac.capture")),
            "The bounded capture child has the pinned identity")
        let data = try Data(
            contentsOf: URL(
                fileURLWithPath: app + "/Contents/Library/LaunchDaemons/" + CaptureServiceInfo.plist
            ))
        let plist =
            try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        check(
            plist["BundleProgram"] as? String == "Contents/MacOS/CherryKeysCaptureService",
            "launchd runs only the bundled broker")
        check(
            plist["Program"] == nil && plist["ProgramArguments"] == nil,
            "No external program or arbitrary arguments are configured")
        check(
            plist["RunAtLoad"] == nil && plist["KeepAlive"] == nil,
            "The daemon is activated on demand")
        check(
            (plist["MachServices"] as? [String: Bool]) == [CaptureServiceInfo.name: true],
            "Only the fixed capture Mach service is advertised")
        print(
            "PASS: \(checks) managed-helper path, signing and launch configuration checks. No service registered and no devices opened."
        )
    }
}
