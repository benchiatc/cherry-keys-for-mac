import Darwin
import Foundation
import IOKit
import IOKit.hid
import SystemConfiguration

// Privilege boundary: only fixed CHERRY HID input is read. No mappings, event
// posting, commands, configuration, services, or user-supplied code are executed.
private var terminationSignal: sig_atomic_t = 0
private let guiExecutable = "/Applications/Cherry Keys for Mac.app/Contents/MacOS/CherryKeysMac"

private struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
private func fail(_ text: String) -> CaptureError { CaptureError(message: text) }
private func consoleUID() -> uid_t? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
        name != "loginwindow", name != "_mbsetupuser", uid != 0, uid != uid_t.max
    else { return nil }
    return uid
}
private struct GUIIdentity: Equatable {
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}
private func identity(pid: pid_t, uid: uid_t) throws -> GUIIdentity {
    guard kill(pid, 0) == 0 else { throw fail("The GUI process is no longer running.") }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let count = withUnsafeMutablePointer(to: &info) {
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, size)
    }
    guard count == size, info.pbi_uid == uid, info.pbi_ruid == uid else {
        throw fail("The GUI process does not belong to the console user.")
    }
    var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = bytes.withUnsafeMutableBytes {
        proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
    }
    guard length > 0, String(cString: bytes) == guiExecutable else {
        throw fail("The GUI executable path does not match the installed application.")
    }
    return GUIIdentity(startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
}
private func checkDescriptor(_ fd: Int32, kind: mode_t, uid: uid_t, permissions: mode_t) throws {
    var st = stat()
    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == kind,
        st.st_uid == uid, st.st_mode & 0o7777 == permissions
    else {
        throw fail("The communication directory has an invalid type, owner, or permissions.")
    }
}
private func connectGUI(directory: String, directoryFD: Int32, uid: uid_t, guiPID: pid_t) throws
    -> Int32
{
    var st = stat()
    guard fstatat(directoryFD, "capture.sock", &st, AT_SYMLINK_NOFOLLOW) == 0,
        st.st_mode & S_IFMT == S_IFSOCK, st.st_uid == uid, st.st_mode & 0o7777 == 0o600
    else {
        throw fail("The GUI socket has an invalid type, owner, or permissions.")
    }
    let path = directory + "/capture.sock"
    let bytes = Array(path.utf8) + [UInt8(0)]
    guard bytes.count <= 104 else { throw fail("The GUI socket path is too long.") }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw fail("Could not create the GUI connection.") }
    do {
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
            throw fail("Could not configure the GUI connection.")
        }
        var noSignal: Int32 = 1
        guard
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                == 0
        else {
            throw fail("Could not configure safe socket writes.")
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else {
                throw fail("Could not connect to the GUI socket (errno \(errno)).")
            }
            var pollFD = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pollFD, 1, 500) == 1 else {
                throw fail("The GUI socket connection timed out.")
            }
            var socketError: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &size) == 0, socketError == 0
            else {
                throw fail("The GUI socket connection failed.")
            }
        }
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == uid else {
            throw fail("The GUI socket peer is not the console user.")
        }
        var peerPID: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &size) == 0,
            size == socklen_t(MemoryLayout<pid_t>.size), peerPID == guiPID
        else {
            throw fail("The GUI socket peer does not match the expected GUI process.")
        }
        return fd
    } catch {
        close(fd)
        throw error
    }
}

private final class Capture {
    private let uid: uid_t
    private let guiPID: pid_t
    private let guiIdentity: GUIIdentity
    private let connectionFD: Int32
    private var manager: IOHIDManager?
    private var opened: [UInt64: IOHIDDevice] = [:]
    private var timer: Timer?
    private var controlInput: DispatchSourceRead?
    private(set) var finished = false
    private let started = ProcessInfo.processInfo.systemUptime
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private var hasHeartbeat = false
    private var discoveryStarted = false
    private var ledWarning: String?
    private var lockLEDs: UInt8?
    private var appliedLEDs: [UInt64: UInt8] = [:]
    private func updateLEDs() {
        guard let state = lockLEDs else { return }
        for (id, device) in opened where isKeyboard(device) && appliedLEDs[id] != state {
            appliedLEDs[id] = state
            let elements =
                IOHIDDeviceCopyMatchingElements(
                    device, [kIOHIDElementUsagePageKey: 8] as CFDictionary, 0) as? [IOHIDElement]
                ?? []
            var found = Set<UInt32>()
            var values: [IOHIDElement: IOHIDValue] = [:]
            for element in elements where IOHIDElementGetType(element) == kIOHIDElementTypeOutput {
                let usage = IOHIDElementGetUsage(element)
                guard usage == 1 || usage == 2 else { continue }
                found.insert(usage)
                let bit: UInt8 = usage == 2 ? 1 : 2
                let value = IOHIDValueCreateWithIntegerValue(
                    kCFAllocatorDefault, element, 0, state & bit != 0 ? 1 : 0)
                values[element] = value
            }
            // Both LEDs share one output report on KW X ULP. Commit together
            // rather than issuing two serialized Bluetooth transactions.
            let failed =
                !values.isEmpty
                && IOHIDDeviceSetValueMultiple(device, values as CFDictionary) != kIOReturnSuccess
            if found != [1, 2] || failed {
                ledWarning =
                    failed
                    ? "Keyboard rejected a lock-indicator update; remapping remains active."
                    : "This CHERRY interface does not expose both standard lock LEDs; remapping remains active."
                _ = message(["type": "ledStatus", "message": ledWarning!])
            }
        }
    }
    private(set) var exitStatus: Int32 = 0
    init(uid: uid_t, guiPID: pid_t, identity: GUIIdentity, connection: Int32) {
        self.uid = uid
        self.guiPID = guiPID
        self.guiIdentity = identity
        connectionFD = connection
    }
    // Each bounded message is sent in one nonblocking write. A partial/full/broken
    // socket must release hardware rather than stall keyboard input.
    @discardableResult private func message(_ fields: [String: Any]) -> Bool {
        guard
            let body = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            body.count < 4095
        else { return false }
        var line = body
        line.append(10)
        let written = line.withUnsafeBytes { Darwin.write(connectionFD, $0.baseAddress, $0.count) }
        return written == line.count
    }
    private func number(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
    private func isCHERRY(_ device: IOHIDDevice) -> Bool {
        CherryDeviceIdentity.accepts(
            vendor: number(device, kIOHIDVendorIDKey), product: number(device, kIOHIDProductIDKey),
            source: number(device, "VendorIDSource"),
            name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "",
            transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
                ?? "")
    }
    private func isBluetoothAuxiliary(_ element: IOHIDElement, _ device: IOHIDDevice) -> Bool {
        CherryDeviceIdentity.isBluetoothAuxiliaryInput(
            page: IOHIDElementGetUsagePage(element), report: IOHIDElementGetReportID(element),
            verifiedKWXBluetooth: isCHERRY(device) && number(device, kIOHIDVendorIDKey) == 0x0687)
    }
    private func isKeyboard(_ device: IOHIDDevice) -> Bool {
        // Some HID services expose primary properties before their element
        // collections become available to a user client opened exclusively.
        IOHIDDeviceConformsTo(device, 1, 6)
            || (number(device, "PrimaryUsagePage") == 1 && number(device, "PrimaryUsage") == 6)
    }
    private func isConsumer(_ device: IOHIDDevice) -> Bool {
        IOHIDDeviceConformsTo(device, 12, 1)
            || (number(device, "PrimaryUsagePage") == 12 && number(device, "PrimaryUsage") == 1)
    }
    private struct Group: Hashable {
        let product: Int
        let location: Int
        let transport: String
    }
    private func group(_ device: IOHIDDevice) -> Group {
        Group(
            product: number(device, kIOHIDProductIDKey),
            location: number(device, kIOHIDLocationIDKey),
            transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
                ?? "")
    }
    private func registryID(_ device: IOHIDDevice) -> UInt64? {
        let service = IOHIDDeviceGetService(device)
        var result: UInt64 = 0
        guard service != 0, IORegistryEntryGetRegistryEntryID(service, &result) == KERN_SUCCESS,
            result != 0
        else { return nil }
        return result
    }
    private func validateCollections(_ device: IOHIDDevice) throws {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement],
            !elements.isEmpty
        else {
            throw fail("Could not inspect CHERRY HID input collections; native input restored.")
        }
        for element in elements {
            let type = IOHIDElementGetType(element)
            guard
                type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Button
                    || type == kIOHIDElementTypeInput_Axis
                    || type == kIOHIDElementTypeInput_ScanCodes
            else { continue }
            let page = IOHIDElementGetUsagePage(element)
            guard page == 0 || page == 7 || page == 12 || isBluetoothAuxiliary(element, device)
            else {
                throw fail(
                    "CHERRY interface includes unsupported input page \(page); native input restored."
                )
            }
        }
    }
    func start() throws {
        // Authenticate a live GUI relay before acquiring any keyboard.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkLiveness()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        let input = DispatchSource.makeReadSource(fileDescriptor: connectionFD, queue: .main)
        input.setEventHandler { [weak self] in self?.checkLiveness() }
        controlInput = input
        input.resume()
        checkLiveness()
    }
    private func startDiscovery() throws {
        discoveryStarted = true
        // IndependentDevices (0x8 in the SDK) prevents a shared manager-open
        // from silently neutralizing a later per-device exclusive open.
        let discovery = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0x8))
        manager = discovery
        IOHIDManagerSetDeviceMatchingMultiple(discovery, CherryDeviceIdentity.matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            discovery,
            { context, _, _, _ in
                guard let context else { return }
                let capture = Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue()
                guard !capture.finished else { return }
                do { try capture.reconcile() } catch {
                    capture.finish(error: error.localizedDescription)
                }
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            discovery,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue().remove(device)
            }, context)
        IOHIDManagerScheduleWithRunLoop(
            discovery, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(discovery, 0)
        guard result == kIOReturnSuccess else {
            throw fail(
                "CHERRY discovery failed: \(String(format: "0x%08X", UInt32(bitPattern: result))).")
        }
        try reconcile()
    }
    private func reconcile() throws {
        guard !finished, let manager else { return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let keyboards = devices.filter { isCHERRY($0) && isKeyboard($0) }
        let groups = Set(keyboards.map(group))
        for device in devices {
            guard isCHERRY(device) else { continue }
            let keyboard = isKeyboard(device)
            let consumer = isConsumer(device) && groups.contains(group(device))
            guard keyboard || consumer else { continue }
            guard let id = registryID(device) else {
                throw fail("CHERRY device identity is unavailable; native input restored.")
            }
            guard opened[id] == nil else { continue }
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            guard result == kIOReturnSuccess else {
                throw fail(
                    "Exclusive CHERRY access failed: \(String(format: "0x%08X", UInt32(bitPattern: result)))."
                )
            }
            opened[id] = device  // Record immediately so any subsequent failure closes it.
            try validateCollections(device)
            IOHIDDeviceRegisterInputValueCallback(
                device,
                { context, result, _, value in
                    guard let context else { return }
                    let capture = Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue()
                    guard result == kIOReturnSuccess else {
                        capture.finish(
                            error: "CHERRY input callback failed; native input restored.")
                        return
                    }
                    capture.receive(value)
                }, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(
                device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        updateLEDs()
        guard
            message([
                "type": "status",
                "message": opened.isEmpty
                    ? "Waiting for a CHERRY keyboard."
                    : "CHERRY capture active. " + (ledWarning ?? ""), "interfaces": opened.count,
            ])
        else {
            finish(error: "The GUI socket is unavailable or full.")
            return
        }
    }
    private func receive(_ value: IOHIDValue) {
        guard !finished else { return }
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let id = registryID(device), opened[id] != nil,
            isCHERRY(device)
        else { return }
        // BLE report 0x11 is vendor data, never a key or a command.
        guard !isBluetoothAuxiliary(element, device) else { return }
        guard let state = HIDValueDecoder.keyState(value) else { return }
        let page = state.page
        guard page == 7 || page == 12 else {
            finish(error: "Unsupported CHERRY input collection; native input restored.")
            return
        }
        let sent = message([
            "type": "input", "vendor": number(device, kIOHIDVendorIDKey), "device": String(id),
            "page": page,
            "usage": state.usage, "down": state.down,
        ])
        if !sent { finish(error: "The GUI socket is unavailable or full.") }
    }
    private func remove(_ device: IOHIDDevice) {
        guard !finished, let pair = opened.first(where: { CFEqual($0.value, device) }) else {
            return
        }
        opened.removeValue(forKey: pair.key)
        appliedLEDs.removeValue(forKey: pair.key)
        IOHIDDeviceRegisterInputValueCallback(pair.value, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(
            pair.value, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(pair.value, 0)
        guard message(["type": "removed", "device": String(pair.key)]),
            message([
                "type": "status",
                "message": opened.isEmpty
                    ? "Waiting for a CHERRY keyboard." : "CHERRY connection changed.",
                "interfaces": opened.count,
            ])
        else {
            finish(error: "The GUI socket is unavailable or full.")
            return
        }
    }
    private func checkLiveness() {
        guard !finished else { return }
        if terminationSignal != 0 {
            finish(error: nil, reason: "Capture interrupted; native input restored.")
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - started >= 4 * 60 * 60 {
            finish(error: nil, reason: "Four-hour capture limit reached; native input restored.")
            return
        }
        guard consoleUID() == uid else {
            finish(error: "The console user changed; native input restored.")
            return
        }
        do {
            guard try identity(pid: guiPID, uid: uid) == guiIdentity else {
                throw fail("The GUI process identity changed.")
            }
        } catch {
            finish(error: error.localizedDescription)
            return
        }
        var bytes = [UInt8](repeating: 0, count: 256)
        // Bound work per tick even if a client floods the heartbeat channel.
        for _ in 0..<16 {
            let count = bytes.withUnsafeMutableBytes {
                Darwin.read(connectionFD, $0.baseAddress, $0.count)
            }
            if count > 0 {
                for byte in bytes.prefix(count) {
                    if byte == 48 {
                        finish(error: nil, reason: "Capture stopped; native input restored.")
                        return
                    }
                    if (65...68).contains(byte) { lockLEDs = byte - 65 }
                    guard byte == 49 || (65...68).contains(byte) else {
                        finish(error: "Invalid heartbeat command; native input restored.")
                        return
                    }
                    lastHeartbeat = now
                    hasHeartbeat = true
                }
            } else if count == 0 {
                finish(error: "The GUI disconnected; native input restored.")
                return
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            } else if errno != EINTR {
                finish(error: "The GUI heartbeat socket failed; native input restored.")
                return
            }
        }
        updateLEDs()
        if now - lastHeartbeat >= 2 {
            finish(error: "The GUI heartbeat expired; native input restored.")
            return
        }
        if hasHeartbeat && !discoveryStarted {
            do { try startDiscovery() } catch { finish(error: error.localizedDescription) }
        }
    }
    func finish(error: String?, reason: String = "Capture stopped; native input restored.") {
        guard !finished else { return }
        finished = true
        exitStatus = error == nil ? 0 : 1
        timer?.invalidate()
        timer = nil
        controlInput?.cancel()
        controlInput = nil
        for device in opened.values {
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(
                device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, 0)
        }
        opened.removeAll()
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
        if let error { _ = message(["type": "error", "message": error]) }
        _ = message(["type": "stopped", "message": error ?? reason])
        CFRunLoopStop(CFRunLoopGetMain())
    }
    deinit { close(connectionFD) }
}

private func main() -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count == 4,
        let uidValue = UInt32(arguments[1]), uidValue != 0, uidValue != UInt32.max,
        let pidValue = Int32(arguments[2]), pidValue > 1,
        arguments[3].hasPrefix("/"), !arguments[3].contains("\0")
    else {
        fputs(
            "Usage: CherryHIDCapture <console-uid> <gui-pid> <absolute-private-socket-directory>\n",
            stderr)
        return 64
    }
    guard geteuid() == 0 else {
        fputs(
            "CherryHIDCapture requires a separately approved administrator launch. No devices opened.\n",
            stderr)
        return 77
    }
    var directoryFD: Int32 = -1
    var connectionFD: Int32 = -1
    defer {
        if directoryFD >= 0 { close(directoryFD) }
        if connectionFD >= 0 { close(connectionFD) }
    }
    var capture: Capture?
    do {
        let uid = uid_t(uidValue)
        let pid = pid_t(pidValue)
        guard consoleUID() == uid else {
            throw fail("The requested user is not the current console user.")
        }
        let gui = try identity(pid: pid, uid: uid)
        directoryFD = open(arguments[3], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw fail("Could not open the private socket directory.") }
        try checkDescriptor(directoryFD, kind: S_IFDIR, uid: uid, permissions: 0o700)
        connectionFD = try connectGUI(
            directory: arguments[3], directoryFD: directoryFD, uid: uid, guiPID: pid)
        close(directoryFD)
        directoryFD = -1
        signal(SIGPIPE, SIG_IGN)
        signal(SIGTERM) { terminationSignal = $0 }
        signal(SIGINT) { terminationSignal = $0 }
        signal(SIGHUP) { terminationSignal = $0 }
        let session = Capture(uid: uid, guiPID: pid, identity: gui, connection: connectionFD)
        capture = session
        connectionFD = -1
        do { try session.start() } catch { session.finish(error: error.localizedDescription) }
        if !session.finished { CFRunLoopRun() }
        return session.exitStatus
    } catch {
        if let capture { capture.finish(error: error.localizedDescription) }
        fputs("CherryHIDCapture: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

exit(main())
