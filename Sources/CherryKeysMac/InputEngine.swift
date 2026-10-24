import AppKit
import ApplicationServices
import Carbon
import IOKit.hid
import IOKit.hidsystem
import ServiceManagement

let syntheticMarker: Int64 = 0x4348_4B4D_4143
let shortcutMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

final class ActionRunner {
    private let queue = DispatchQueue(label: "CherryKeysMac.actions")
    private let lock = NSLock()
    private var generation = 0
    private var busy = false
    var onResult: ((String) -> Void)?
    func cancel() {
        lock.lock()
        generation += 1
        lock.unlock()
    }
    private func current(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }
    func run(_ assignment: Assignment) {
        lock.lock()
        guard !busy else {
            lock.unlock()
            return
        }
        busy = true
        let token = generation
        lock.unlock()
        queue.async { [self] in
            var message = "Executed \(assignment.action.title)"
            do { try perform(assignment, token: token) } catch {
                message = error.localizedDescription
            }
            lock.lock()
            busy = false
            lock.unlock()
            DispatchQueue.main.async { self.onResult?(message) }
        }
    }
    private func sendKey(_ code: Int, down: Bool, flags: CGEventFlags = []) {
        guard
            let e = CGEvent(
                keyboardEventSource: CGEventSource(stateID: .privateState),
                virtualKey: CGKeyCode(code), keyDown: down)
        else { return }
        if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code) { e.type = .flagsChanged }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.post(tap: .cgSessionEventTap)
    }
    private func wait(_ seconds: Double, token: Int) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if !current(token) { return false }
            Thread.sleep(forTimeInterval: min(0.01, end.timeIntervalSinceNow.clamped(to: 0...30)))
        }
        return current(token)
    }
    private func perform(_ a: Assignment, token: Int) throws {
        guard current(token) else { return }
        switch a.action {
        case .application, .file, .website:
            let url = a.action == .website ? URL(string: a.value)! : URL(fileURLWithPath: a.value)
            DispatchQueue.main.async {
                if !NSWorkspace.shared.open(url) {
                    self.onResult?("Could not open \(url.lastPathComponent)")
                }
            }
        case .text:
            guard CGPreflightPostEventAccess() else {
                throw AppError.message("Accessibility permission is needed to insert text.")
            }
            // Each Character stays intact, including surrogate pairs and composed accents.
            for character in a.value {
                guard current(token) else { return }
                if character == "\n" || character == "\r\n" {
                    sendKey(36, down: true)
                    sendKey(36, down: false)
                    continue
                }
                if character == "\t" {
                    sendKey(48, down: true)
                    sendKey(48, down: false)
                    continue
                }
                let units = Array(String(character).utf16)
                // CGEvent's Unicode payload is bounded; very large combining clusters are split at Unicode scalars.
                let chunks: [[UInt16]] =
                    units.count <= 20
                    ? [units] : String(character).unicodeScalars.map { Array(String($0).utf16) }
                for chunk in chunks {
                    for down in [true, false] {
                        let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
                        e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                        e.flags = []
                        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                        e.post(tap: .cgSessionEventTap)
                    }
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
        case .macro:
            var held: Set<Int> = []
            defer { for code in held { sendKey(code, down: false) } }
            for step in a.steps {
                guard wait(step.delay, token: token) else { return }
                sendKey(step.code, down: step.down, flags: CGEventFlags(rawValue: step.flags))
                if step.down { held.insert(step.code) } else { held.remove(step.code) }
            }
        case .media:
            for down in [true, false] {
                let state = down ? 0xA : 0xB
                let e = NSEvent.otherEvent(
                    with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 8,
                    data1: (a.mediaCode << 16) | (state << 8), data2: -1)?.cgEvent
                e?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                e?.post(tap: .cgSessionEventTap)
            }
        case .browserBack, .browserForward:
            let code = a.action == .browserBack ? 33 : 30
            sendKey(code, down: true, flags: .maskCommand)
            sendKey(code, down: false, flags: .maskCommand)
        case .lock:
            let flags: CGEventFlags = [.maskControl, .maskCommand]
            sendKey(12, down: true, flags: flags)
            sendKey(12, down: false, flags: flags)
        case .sleep:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["sleepnow"]
            try task.run()
        case .modifier: break  // Routed as held state by HIDRouter.
        case .macAction:
            guard let choice = MacAction(rawValue: a.value) else { return }
            let (code, flags) = choice.shortcut
            sendKey(code, down: true, flags: CGEventFlags(rawValue: flags))
            sendKey(code, down: false, flags: CGEventFlags(rawValue: flags))
        case .shortcut:
            sendKey(a.outputKey, down: true, flags: CGEventFlags(rawValue: a.modifiers))
            sendKey(a.outputKey, down: false, flags: CGEventFlags(rawValue: a.modifiers))
        case .disable: break
        }
    }
}
extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// The GUI stays unprivileged. An approved, certificate-pinned macOS service starts
/// a bounded capture child. The child exits when this socket stops responding.
final class InputEngine {
    private var listener: DispatchSourceRead?
    private var input: DispatchSourceRead?
    private var connection: Int32 = -1
    private var directory: URL?
    private var serviceConnection: NSXPCConnection?
    private var heartbeat: Timer?
    private var lastIndicatorByte: UInt8?
    private var observers: [NSObjectProtocol] = []
    private var recovery = CaptureRecovery()
    private var resumeTimer: Timer?
    private var buffer = Data()
    private var session = UUID()
    private var started = Date()
    private(set) var running = false
    var assignments: [Assignment] = [] { didSet { router.assignments = assignments } }
    var onPause: (() -> Void)?
    var onSuspend: (() -> Void)?
    var onStatus: ((String) -> Void)?
    let runner = ActionRunner()
    let router = HIDRouter()
    init() {
        router.action = { [weak self] in self?.runner.run($0) }
        router.emergency = { [weak self] in
            self?.pause("Remapping paused with the emergency shortcut.")
        }
        router.unsupported = { [weak self] in self?.pause($0) }
        let events: [(Notification.Name, CaptureRecovery.Event)] = [
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.sessionDidResignActiveNotification, .resignSession),
            (NSWorkspace.sessionDidBecomeActiveNotification, .activateSession),
        ]
        for (name, event) in events {
            observers.append(
                NSWorkspace.shared.notificationCenter.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in self?.workspaceChanged(event) })
        }

    }
    func start() throws {
        guard !running else { return }
        guard Bundle.main.bundlePath == "/Applications/Cherry Keys for Mac.app" else {
            throw AppError.message(
                "Run the installed app at /Applications/Cherry Keys for Mac.app. Development/package copies cannot start privileged capture."
            )
        }
        guard AXIsProcessTrusted() && CGPreflightPostEventAccess() else {
            throw AppError.message(
                "Accessibility is not approved for this build. Remove its old Accessibility entry and add /Applications/Cherry Keys for Mac.app, then reopen it."
            )
        }
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            throw AppError.message(
                "Allow this installed app in Input Monitoring, then quit and reopen it. Input Monitoring and Accessibility are separate permissions."
            )
        }
        guard !IsSecureEventInputEnabled() else {
            throw AppError.message(
                "Secure Keyboard Entry is active. Native keyboard input is kept; remapping stays paused."
            )
        }
        guard SMAppService.daemon(plistName: CaptureServiceInfo.plist).status == .enabled else {
            throw AppError.message(
                "Choose Set up helper and approve it in macOS Login Items & Extensions. Setup is needed once; Pause and Enable then work without a password."
            )
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/MacOS/CherryKeysHIDCapture")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw AppError.message("The installed app is missing its native CHERRY capture helper.")
        }
        let id = UUID()
        session = id
        started = Date()
        buffer = Data()
        let directory = URL(fileURLWithPath: "/private/tmp/ckm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        self.directory = directory
        do {
            let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socketFD >= 0 else {
                throw AppError.message("Could not create local capture socket.")
            }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let path = directory.appendingPathComponent("capture.sock").path
            let bytes = Array(path.utf8) + [UInt8(0)]
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                Darwin.close(socketFD)
                throw AppError.message("Capture socket path is too long.")
            }
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                bytes.withUnsafeBytes { destination.copyBytes(from: $0) }
            }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 && Darwin.listen(socketFD, 4) == 0 else {
                Darwin.close(socketFD)
                throw AppError.message("Could not listen on local capture socket.")
            }
            guard
                chmod(path, 0o600) == 0 && fcntl(socketFD, F_SETFL, O_NONBLOCK) == 0
                    && fcntl(socketFD, F_SETFD, FD_CLOEXEC) == 0
            else {
                Darwin.close(socketFD)
                throw AppError.message("Could not protect the local capture socket.")
            }
            let listener = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .main)
            listener.setCancelHandler { Darwin.close(socketFD) }
            listener.setEventHandler { [weak self] in self?.accept(socketFD, session: id) }
            self.listener = listener
            listener.resume()
            running = true
            let service = NSXPCConnection(
                machServiceName: CaptureServiceInfo.name, options: .privileged)
            service.setCodeSigningRequirement(
                try CaptureServiceInfo.requirement(identifier: CaptureServiceInfo.name))
            service.remoteObjectInterface = NSXPCInterface(with: CherryCaptureServiceProtocol.self)
            service.invalidationHandler = { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.running, self.session == id else { return }
                    self.pause(
                        "Capture service disconnected. Check helper setup in Login Items & Extensions."
                    )
                }
            }
            service.interruptionHandler = service.invalidationHandler
            serviceConnection = service
            service.resume()
            let proxy =
                service.remoteObjectProxyWithErrorHandler { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self, self.running, self.session == id else { return }
                        self.pause(
                            "Could not reach the capture service: \(error.localizedDescription)")
                    }
                } as? CherryCaptureServiceProtocol
            guard let proxy else {
                throw AppError.message("The capture service interface is unavailable.")
            }
            proxy.startCapture(directory: directory.path) { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    guard let self, self.running, self.session == id else { return }
                    self.pause(error)
                }
            }
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            heartbeat = timer
            RunLoop.main.add(timer, forMode: .common)
            onStatus?("Starting CHERRY capture with the approved helper…")
        } catch {
            stop()
            throw error
        }
    }
    private func accept(_ socketFD: Int32, session id: UUID) {
        guard running && session == id else { return }
        while true {
            let client = Darwin.accept(socketFD, nil, nil)
            if client < 0 { return }
            var uid: uid_t = 99999
            var gid: gid_t = 99999
            guard getpeereid(client, &uid, &gid) == 0 && uid == 0 && connection < 0 else {
                Darwin.close(client)
                continue
            }
            var noSigPipe: Int32 = 1
            guard
                fcntl(client, F_SETFL, O_NONBLOCK) == 0 && fcntl(client, F_SETFD, FD_CLOEXEC) == 0
                    && setsockopt(
                        client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                        socklen_t(MemoryLayout<Int32>.size)) == 0
            else {
                Darwin.close(client)
                pause("Could not protect the local helper connection.")
                return
            }
            connection = client
            let input = DispatchSource.makeReadSource(fileDescriptor: client, queue: .main)
            input.setCancelHandler { Darwin.close(client) }
            input.setEventHandler { [weak self] in self?.read(client, session: id) }
            self.input = input
            input.resume()
            listener?.cancel()
            listener = nil
            sendIndicators(force: true)
            return
        }
    }
    private func read(_ fd: Int32, session id: UUID) {
        guard running && session == id else { return }
        var bytes = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 {
                pause("CHERRY capture ended. Native input restored.")
                return
            }
            if count < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK {
                    pause("Local capture connection failed. Native input restored.")
                }
                return
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 1_048_576 else {
                pause("Capture queue overflowed; native input restored.")
                return
            }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    let type = json["type"] as? String
                else {
                    pause("Invalid capture message; native input restored.")
                    return
                }
                switch type {
                case "input":
                    guard let vendor = json["vendor"] as? Int,
                        CherryDeviceIdentity.acceptsRelayVendor(vendor),
                        let device = json["device"] as? String, let deviceID = UInt64(device),
                        let page = json["page"] as? UInt32, let usage = json["usage"] as? UInt32,
                        let down = json["down"] as? Bool
                    else {
                        pause("Invalid CHERRY source metadata; native input restored.")
                        return
                    }
                    router.receive(
                        vendor: vendor, device: deviceID, page: page, usage: usage, down: down,
                        physicalFlags: CGEventSource.flagsState(.hidSystemState))
                    // Lock LEDs should not wait for the periodic heartbeat.
                    sendIndicators(force: false)
                case "removed":
                    if let device = json["device"] as? String, let deviceID = UInt64(device) {
                        router.releaseDevice(deviceID)
                        runner.cancel()
                    }
                case "ledStatus":
                    onStatus?(
                        json["message"] as? String ?? "Keyboard indicator update unavailable.")
                case "status":
                    onStatus?(json["message"] as? String ?? "CHERRY-only capture active.")
                case "error", "stopped":
                    pause(
                        json["message"] as? String
                            ?? "CHERRY capture stopped. Native input restored.")
                    return
                default:
                    pause("Unknown capture message; native input restored.")
                    return
                }
                if !running { return }
            }
        }
    }
    private func tick() {
        guard running else { return }
        switch CaptureGate.decide(
            connected: connection >= 0, secureInput: IsSecureEventInputEnabled(),
            canPost: CGPreflightPostEventAccess(), elapsed: Date().timeIntervalSince(started))
        {
        case .awaitHelper: return
        case .stopHelperTimeout:
            pause("Capture service startup timed out. Check helper setup; remapping stays paused.")
            return
        case .stopSecureEntry:
            suspend(
                "Waiting for Secure Keyboard Entry to end; remapping will resume automatically.")
            return
        case .stopPermissionLoss:
            pause("Keyboard output permission changed. Native input restored.")
            return
        case .heartbeat: break
        }
        sendIndicators(force: true)
    }
    private func sendIndicators(force: Bool) {
        guard running, connection >= 0 else { return }
        let indicators = router.lockIndicators(
            physicalFlags: CGEventSource.flagsState(.hidSystemState))
        var value: UInt8 = 65 + (indicators.caps ? 1 : 0) + (indicators.num ? 2 : 0)
        guard force || lastIndicatorByte != value else { return }
        if Darwin.write(connection, &value, 1) != 1 {
            pause("Capture heartbeat failed. Native input restored.")
        } else {
            lastIndicatorByte = value
        }
    }
    private func workspaceChanged(_ event: CaptureRecovery.Event) {
        recovery.observe(event)
        switch event {
        case .sleep, .resignSession:
            if running { suspend("Waiting for wake/unlock; remapping will resume automatically.") }
        case .wake, .activateSession:
            resumeIfReady()
        }
    }
    private func suspend(_ message: String) {
        stop()
        recovery.suspend()
        onSuspend?()
        onStatus?(message)
        // Notifications stay registered while capture is stopped. A timer also
        // covers secure-input ending without a workspace activation notification.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.resumeIfReady()
        }
        resumeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func resumeIfReady() {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let onConsole = session?[kCGSessionOnConsoleKey as String] as? Bool ?? false
        guard recovery.canResume(secureInput: IsSecureEventInputEnabled(), onConsole: onConsole)
        else { return }
        recovery.cancel()
        resumeTimer?.invalidate()
        resumeTimer = nil
        do { try start() } catch {
            pause("Could not resume remapping: \(error.localizedDescription)")
        }
    }
    private func pause(_ message: String) {
        stop()
        onPause?()
        onStatus?(message)
    }
    func stop() {
        recovery.cancel()
        resumeTimer?.invalidate()
        resumeTimer = nil
        lastIndicatorByte = nil
        running = false
        session = UUID()
        heartbeat?.invalidate()
        heartbeat = nil
        runner.cancel()
        if connection >= 0 {
            var stop: UInt8 = 48
            _ = Darwin.write(connection, &stop, 1)
        }
        input?.cancel()
        input = nil
        connection = -1
        listener?.cancel()
        listener = nil
        serviceConnection?.invalidate()
        serviceConnection = nil
        router.releaseAll()
        buffer = Data()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
    deinit {
        stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

struct Hardware {
    static func cherryDevices() -> [String] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(manager, CherryDeviceIdentity.matching as CFArray)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(
            Set(
                devices.map { d in
                    let name =
                        IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String
                        ?? "CHERRY keyboard"
                    let transport =
                        IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String
                        ?? "Unknown"
                    let pid =
                        (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? NSNumber)?
                        .intValue ?? 0
                    let vendor =
                        (IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? NSNumber)?
                        .intValue ?? 0
                    return "\(name) · \(transport) · \(String(format: "%04X:%04X", vendor, pid))"
                })
        ).sorted()
    }
}
