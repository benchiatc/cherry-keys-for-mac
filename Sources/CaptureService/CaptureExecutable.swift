import Darwin
import Foundation
import Security

/// A validated executable snapshot in a root-private directory. Never execute a
/// user-writable pathname after validating its signature (TOCTOU).
final class CaptureExecutable {
    let directory: URL
    var url: URL { directory.appendingPathComponent("capture") }

    init(source: String = CaptureServiceInfo.capturePath) throws {
        var template = Array("/private/tmp/cherry-capture-XXXXXXXX".utf8CString)
        guard let path = mkdtemp(&template) else { throw POSIXError(.EIO) }
        directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        do {
            let input = open(source, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard input >= 0 else { throw POSIXError(.EACCES) }
            defer { close(input) }
            var metadata = stat()
            guard fstat(input, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
                metadata.st_size > 0, metadata.st_size <= 64 * 1024 * 1024
            else { throw POSIXError(.EINVAL) }
            let output = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o500)
            guard output >= 0 else { throw POSIXError(.EACCES) }
            defer { close(output) }
            var remaining = metadata.st_size
            var buffer = [UInt8](repeating: 0, count: 65536)
            while remaining > 0 {
                let count = read(input, &buffer, min(buffer.count, Int(remaining)))
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                var offset = 0
                try buffer.withUnsafeBytes { bytes in
                    while offset < count {
                        let written = write(
                            output, bytes.baseAddress!.advanced(by: offset), count - offset)
                        if written < 0 && errno == EINTR { continue }
                        guard written > 0 else { throw POSIXError(.EIO) }
                        offset += written
                    }
                }
                remaining -= off_t(count)
            }
            let requirement = try CaptureServiceInfo.requirement(
                identifier: "local.cherrykeys.mac.capture")
            var code: SecStaticCode?
            var parsed: SecRequirement?
            guard
                SecRequirementCreateWithString(requirement as CFString, [], &parsed)
                    == errSecSuccess,
                SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
                let code, let parsed,
                SecStaticCodeCheckValidity(
                    code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                    parsed) == errSecSuccess
            else {
                throw NSError(
                    domain: CaptureServiceInfo.name, code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Capture executable signature verification failed."
                    ])
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}
