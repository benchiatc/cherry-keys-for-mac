import CryptoKit
import Foundation
import Security

enum CaptureServiceInfo {
    static let name = "local.cherrykeys.mac.capture-service"
    static let plist = name + ".plist"
    static let appPath = "/Applications/Cherry Keys for Mac.app"
    static let guiPath = appPath + "/Contents/MacOS/CherryKeysMac"
    static let capturePath = appPath + "/Contents/MacOS/CherryKeysHIDCapture"
    static let version = "1"

    // Pin our actual signing certificate, including local development builds.
    // An identifier alone or an arbitrary intact ad-hoc signature is insufficient.
    static func requirement(identifier: String) throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let dict = info as? [String: Any],
            let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else {
            throw NSError(
                domain: name, code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "A stable signing certificate is required for the capture service."
                ])
        }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map {
            String(format: "%02x", $0)
        }.joined()
        return "identifier \"\(identifier)\" and certificate leaf = H\"\(digest)\""
    }

    static func validSocketDirectory(_ path: String) -> Bool {
        let prefix = "/private/tmp/ckm-"
        guard path.hasPrefix(prefix) else { return false }
        let suffix = String(path.dropFirst(prefix.count))
        return UUID(uuidString: suffix) != nil && suffix.count == 36
    }
}

@objc protocol CherryCaptureServiceProtocol {
    func startCapture(directory: String, withReply reply: @escaping (String?) -> Void)
}
