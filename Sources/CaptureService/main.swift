import Darwin
import Foundation
import Security
import SystemConfiguration

// This broker never reads HID input. It launches only the signed, fixed-path
// bounded capture executable for an authenticated current-console GUI.
private func consoleUser() -> uid_t? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
        name != "loginwindow", name != "_mbsetupuser", uid != 0, uid != uid_t.max
    else { return nil }
    return uid
}

private func isConsoleGUI(_ connection: NSXPCConnection) -> Bool {
    let uid = connection.effectiveUserIdentifier
    let pid = connection.processIdentifier
    guard uid != 0, pid > 1, consoleUser() == uid else { return false }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard
        withUnsafeMutablePointer(to: &info, { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, size) })
            == size,
        info.pbi_uid == uid, info.pbi_ruid == uid
    else { return false }
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
    return length > 0 && String(cString: path) == CaptureServiceInfo.guiPath
}

private final class Broker {
    static let shared = Broker()
    let queue = DispatchQueue(label: "CherryKeys.capture-broker")
    private var process: Process?
    private var executable: CaptureExecutable?
    private var owner: UUID?
    // Queue-confined. A new request waits for the previous bounded child to
    // release the device; no two exclusive capture children are left running.
    private func stopCurrent() {
        if let process, process.isRunning {
            process.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                usleep(10_000)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        process = nil
        owner = nil
        executable = nil
    }
    func start(
        owner: UUID, connection: NSXPCConnection, directory: String,
        reply: @escaping (String?) -> Void
    ) {
        queue.async {
            guard isConsoleGUI(connection), CaptureServiceInfo.validSocketDirectory(directory)
            else {
                reply("Invalid capture client or socket directory.")
                return
            }
            do {
                let executable = try CaptureExecutable()
                self.stopCurrent()
                // The bounded child rechecks console/PID/start time, directory,
                // socket ownership and the socket peer before opening any HID device.
                let child = Process()
                child.executableURL = executable.url
                child.arguments = [
                    String(connection.effectiveUserIdentifier),
                    String(connection.processIdentifier), directory,
                ]
                child.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
                child.standardInput = FileHandle.nullDevice
                child.standardOutput = FileHandle.nullDevice
                child.standardError = FileHandle.nullDevice
                try child.run()
                self.executable = executable
                self.process = child
                self.owner = owner
                reply(nil)
            } catch { reply(error.localizedDescription) }
        }
    }
    func stop(owner: UUID) {
        queue.async { if self.owner == owner { self.stopCurrent() } }
    }
}

private final class ClientSession: NSObject, CherryCaptureServiceProtocol {
    let id = UUID()
    weak var connection: NSXPCConnection?
    func startCapture(directory: String, withReply reply: @escaping (String?) -> Void) {
        guard let connection, isConsoleGUI(connection),
            CaptureServiceInfo.validSocketDirectory(directory)
        else {
            reply("Only the installed CHERRY app for the current console user can start capture.")
            return
        }
        Broker.shared.start(owner: id, connection: connection, directory: directory, reply: reply)
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        guard isConsoleGUI(connection) else { return false }
        let client = ClientSession()
        client.connection = connection
        connection.exportedInterface = NSXPCInterface(with: CherryCaptureServiceProtocol.self)
        connection.exportedObject = client
        connection.invalidationHandler = { Broker.shared.stop(owner: client.id) }
        connection.interruptionHandler = { Broker.shared.stop(owner: client.id) }
        connection.resume()
        return true
    }
}

guard CommandLine.arguments.count == 1 else {
    fputs("This service accepts no command-line arguments.\n", stderr)
    exit(64)
}
guard geteuid() == 0 else {
    fputs("This service must be started by macOS after helper setup. No devices opened.\n", stderr)
    exit(77)
}
do {
    let listener = NSXPCListener(machServiceName: CaptureServiceInfo.name)
    // macOS checks each peer's audit-token identity before the delegate runs.
    listener.setConnectionCodeSigningRequirement(
        try CaptureServiceInfo.requirement(identifier: "local.cherrykeys.mac"))
    let delegate = ServiceDelegate()
    listener.delegate = delegate
    listener.resume()
    RunLoop.main.run()
} catch {
    fputs("Capture service signing validation failed.\n", stderr)
    exit(1)
}
