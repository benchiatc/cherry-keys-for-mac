import AppKit

/// Exact source attribution comes from the IOHIDDevice callback, before Quartz merges devices.
struct HIDPress: Hashable {
    let device: UInt64
    let page: UInt32
    let usage: UInt32
}

enum HIDKeyMap {
    static let keyboard: [UInt32: Int] = [
        0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3, 0x0a: 5, 0x0b: 4, 0x0c: 34,
        0x0d: 38, 0x0e: 40, 0x0f: 37, 0x10: 46, 0x11: 45, 0x12: 31, 0x13: 35, 0x14: 12, 0x15: 15,
        0x16: 1, 0x17: 17, 0x18: 32, 0x19: 9, 0x1a: 13, 0x1b: 7, 0x1c: 16, 0x1d: 6,
        0x1e: 18, 0x1f: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22, 0x24: 26, 0x25: 28, 0x26: 25,
        0x27: 29,
        0x28: 36, 0x29: 53, 0x2a: 51, 0x2b: 48, 0x2c: 49, 0x2d: 27, 0x2e: 24, 0x2f: 33, 0x30: 30,
        0x31: 42, 0x32: 42, 0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44, 0x39: 57,
        0x3a: 122, 0x3b: 120, 0x3c: 99, 0x3d: 118, 0x3e: 96, 0x3f: 97, 0x40: 98, 0x41: 100,
        0x42: 101, 0x43: 109, 0x44: 103, 0x45: 111, 0x46: 105, 0x47: 107, 0x48: 113,
        0x49: 114, 0x4a: 115, 0x4b: 116, 0x4c: 117, 0x4d: 119, 0x4e: 121, 0x4f: 124, 0x50: 123,
        0x51: 125, 0x52: 126,
        0x53: 71, 0x54: 75, 0x55: 67, 0x56: 78, 0x57: 69, 0x58: 76, 0x59: 83, 0x5a: 84, 0x5b: 85,
        0x5c: 86, 0x5d: 87, 0x5e: 88, 0x5f: 89, 0x60: 91, 0x61: 92, 0x62: 82, 0x63: 65, 0x64: 10,
        0x65: 110, 0x67: 81,
        0x68: 106, 0x69: 64, 0x6a: 79, 0x6b: 80, 0x6c: 90, 0x85: 95, 0x87: 94, 0x89: 93, 0x8a: 104,
        0x8b: 102,
        0xe0: 59, 0xe1: 56, 0xe2: 58, 0xe3: 55, 0xe4: 62, 0xe5: 60, 0xe6: 61, 0xe7: 54,
    ]
    static let media: [UInt32: Int] = [
        0xb0: 16, 0xb1: 16, 0xb5: 17, 0xb6: 18, 0xcd: 16, 0xe2: 7, 0xe9: 0, 0xea: 1, 0x6f: 2,
        0x70: 3,
    ]
    static let modifier: [UInt32: CGEventFlags] = [
        0xe0: .maskControl, 0xe1: .maskShift, 0xe2: .maskAlternate, 0xe3: .maskCommand,
        0xe4: .maskControl, 0xe5: .maskShift, 0xe6: .maskAlternate, 0xe7: .maskCommand,
    ]
}

/// Does not install a global key filter. Only a verified CHERRY HID source can enter this router.
final class HIDRouter {
    enum Output {
        case key(Int, UInt64)
        case media(Int)
        case action(Assignment)
        case disabled
    }
    var assignments: [Assignment] = []
    var emit: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    var action: (Assignment) -> Void = { _ in }
    var unsupported: (String) -> Void = { _ in }
    var emergency: () -> Void = {}
    private var held: [HIDPress: Output] = [:]
    private var modifiers: [HIDPress: (code: Int, bit: CGEventFlags)] = [:]
    private(set) var numLock = true
    func lockIndicators(physicalFlags: CGEventFlags) -> (caps: Bool, num: Bool) {
        let physicalCaps = physicalFlags.contains(.maskAlphaShift)
        if let prior = lastPhysicalCaps, prior != physicalCaps { caps = nil }
        lastPhysicalCaps = physicalCaps
        return (caps ?? physicalCaps, numLock)
    }
    static let keypadNavigation: [UInt32: Int] = [
        0x59: 119, 0x5a: 125, 0x5b: 121, 0x5c: 123, 0x5e: 124, 0x5f: 115, 0x60: 126, 0x61: 116,
        0x62: 114, 0x63: 117,
    ]
    private var caps: Bool?
    private var lastPhysicalCaps: Bool?
    private var repeatKey: HIDPress?
    private var repeatTimer: Timer?
    private var baseFlags: CGEventFlags = []
    private let eventSource = CGEventSource(stateID: .privateState)

    private var flags: CGEventFlags {
        var f = baseFlags
        for m in modifiers.values { f.formUnion(m.bit) }
        if let caps { if caps { f.insert(.maskAlphaShift) } else { f.remove(.maskAlphaShift) } }
        return f
    }
    func receive(
        vendor: Int, device: UInt64, page: UInt32, usage: UInt32, down: Bool,
        physicalFlags: CGEventFlags
    ) {
        // A non-CHERRY source never produces or suppresses an event.
        guard CherryDeviceIdentity.acceptsRelayVendor(vendor) else { return }
        guard page == 7 || page == 12 else { return }
        guard usage > 3 || page != 7 else { return }  // Null and boot-keyboard rollover slots.
        let physicalCaps = physicalFlags.contains(.maskAlphaShift)
        if let prior = lastPhysicalCaps, prior != physicalCaps { caps = nil }
        lastPhysicalCaps = physicalCaps
        baseFlags = physicalFlags
        let key = HIDPress(device: device, page: page, usage: usage)
        if page == 7, let bit = HIDKeyMap.modifier[usage], let code = HIDKeyMap.keyboard[usage] {
            if down {
                guard modifiers[key] == nil, held[key] == nil else { return }
                let assignment = assignments.first {
                    $0.enabled && $0.trigger == Trigger(kind: .key, code: code)
                }
                if assignment?.action == .disable {
                    held[key] = .disabled
                    return
                }
                let destination = assignment?.action == .modifier ? assignment!.outputKey : code
                let outputBit =
                    HIDKeyMap.modifier.first { HIDKeyMap.keyboard[$0.key] == destination }?.value
                    ?? bit
                modifiers[key] = (destination, outputBit)
                sendKey(destination, down: true, flags: flags, modifier: true)
            } else {
                held.removeValue(forKey: key)
                if let output = modifiers.removeValue(forKey: key) {
                    if !modifiers.values.contains(where: { $0.code == output.code }) {
                        sendKey(output.code, down: false, flags: flags, modifier: true)
                    }
                }
            }
            return
        }
        if page == 7 && usage == 0x39 {
            if down && held[key] == nil {
                caps = !flags.contains(.maskAlphaShift)
                held[key] = .disabled
                sendKey(57, down: true, flags: flags, modifier: true)
            } else if !down {
                held.removeValue(forKey: key)
            }
            return
        }
        if page == 7 && usage == 0x53
            && !assignments.contains(where: {
                $0.enabled && $0.trigger == Trigger(kind: .key, code: 71)
            })
        {
            if down && held[key] == nil {
                numLock.toggle()
                held[key] = .disabled
            } else if !down {
                held.removeValue(forKey: key)
            }
            return
        }
        // Duplicate HID state must not relaunch actions or create repeat storms.
        if down, held[key] != nil { return }
        if !down {
            guard let output = held.removeValue(forKey: key) else { return }
            if repeatKey == key { cancelRepeat() }
            release(output, performAction: true)
            return
        }
        let trigger: Trigger
        var inheritedTrigger: Trigger?
        let normal: Output
        if page == 7, let code = HIDKeyMap.keyboard[usage] {
            trigger = Trigger(kind: .key, code: code)
            if !numLock && usage == 0x5d {
                normal = .disabled
            } else {
                normal = .key(!numLock ? (Self.keypadNavigation[usage] ?? code) : code, UInt64.max)
            }
            if code == 53
                && flags.intersection(shortcutMask) == [.maskControl, .maskAlternate, .maskCommand]
            {
                emergency()
                return
            }
        } else if page == 12, let code = HIDKeyMap.media[usage] {
            trigger = Trigger(kind: .media, code: code)
            normal = .media(code)
        } else if page == 12, let control = ConsumerControl(rawValue: Int(usage)) {
            trigger = Trigger(kind: .consumer, code: control.rawValue)
            inheritedTrigger = control.functionTrigger
            normal = .action(control.defaultAssignment)
        } else {
            unsupported(
                "Unsupported CHERRY key (HID page \(page), usage 0x\(String(usage, radix:16))). Remapping paused and native input restored."
            )
            return
        }
        let a =
            flags.intersection(shortcutMask).isEmpty
            ? (assignments.first { $0.enabled && $0.trigger == trigger }
                ?? assignments.first { $0.enabled && $0.trigger == inheritedTrigger }) : nil
        let output: Output
        if let a {
            switch a.action {
            case .shortcut: output = .key(a.outputKey, a.modifiers)
            case .disable: output = .disabled
            default: output = .action(a)
            }
        } else {
            output = normal
        }
        held[key] = output
        switch output {
        case .key(let code, let custom):
            sendKey(
                code, down: true,
                flags: custom == UInt64.max ? flags : CGEventFlags(rawValue: custom))
            beginRepeat(key)
        case .media(let code):
            sendMedia(code, down: true)
            if [0, 1, 2, 3].contains(code) { beginRepeat(key) }
        default: break
        }
    }
    private func release(_ output: Output, performAction: Bool) {
        switch output {
        case .key(let code, let custom):
            let anotherHeld = held.values.contains {
                if case .key(let other, _) = $0 { return other == code }
                return false
            }
            if !anotherHeld {
                sendKey(
                    code, down: false,
                    flags: custom == UInt64.max ? flags : CGEventFlags(rawValue: custom))
            }
        case .media(let code): sendMedia(code, down: false)
        case .action(let a): if performAction { action(a) }
        case .disabled: break
        }
    }
    private func sendKey(
        _ code: Int, down: Bool, flags: CGEventFlags, modifier: Bool = false, repeated: Bool = false
    ) {
        guard
            let event = CGEvent(
                keyboardEventSource: eventSource, virtualKey: CGKeyCode(code), keyDown: down)
        else { return }
        event.flags = flags
        if modifier { event.type = .flagsChanged }
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        emit(event)
    }
    private func sendMedia(_ code: Int, down: Bool, repeated: Bool = false) {
        guard
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)), timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8,
                data1: (code << 16) | ((down ? 0xa : 0xb) << 8) | (repeated ? 1 : 0), data2: -1)?
                .cgEvent
        else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        emit(event)
    }
    private func beginRepeat(_ key: HIDPress) {
        cancelRepeat()
        repeatKey = key
        guard NSEvent.keyRepeatInterval > 0 && NSEvent.keyRepeatDelay < 100 else { return }
        let timer = Timer(timeInterval: max(0.01, NSEvent.keyRepeatInterval), repeats: true) {
            [weak self] _ in
            guard let self, let k = self.repeatKey, let output = self.held[k] else { return }
            self.baseFlags = CGEventSource.flagsState(.hidSystemState)
            switch output {
            case .key(let code, let custom):
                self.sendKey(
                    code, down: true,
                    flags: custom == UInt64.max ? self.flags : CGEventFlags(rawValue: custom),
                    repeated: true)
            case .media(let code): self.sendMedia(code, down: true, repeated: true)
            default: break
            }
        }
        timer.fireDate = Date().addingTimeInterval(NSEvent.keyRepeatDelay)
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func cancelRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatKey = nil
    }
    func releaseDevice(_ device: UInt64) {
        for key in Array(held.keys) where key.device == device {
            if repeatKey == key { cancelRepeat() }
            if let output = held.removeValue(forKey: key) { release(output, performAction: false) }
        }
        for key in Array(modifiers.keys) where key.device == device {
            if let output = modifiers.removeValue(forKey: key),
                !modifiers.values.contains(where: { $0.code == output.code })
            {
                sendKey(output.code, down: false, flags: flags, modifier: true)
            }
        }
    }
    func releaseAll() {
        cancelRepeat()
        let ids = Set(held.keys.map(\.device) + modifiers.keys.map(\.device))
        for id in ids { releaseDevice(id) }
        caps = nil
        lastPhysicalCaps = nil
    }
    deinit { cancelRepeat() }
}
