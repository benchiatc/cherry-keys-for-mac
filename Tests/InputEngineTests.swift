import AppKit

@main
struct InputEngineTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }
    static func main() {
        let router = HIDRouter()
        var events: [CGEvent] = []
        var actions: [Assignment] = []
        var errors: [String] = []
        router.emit = { events.append($0) }
        router.action = { actions.append($0) }
        router.unsupported = { errors.append($0) }
        func key(
            _ vendor: Int = 0x046a, _ device: UInt64 = 1, _ usage: UInt32, _ down: Bool,
            _ flags: CGEventFlags = []
        ) {
            router.receive(
                vendor: vendor, device: device, page: 7, usage: usage, down: down,
                physicalFlags: flags)
        }
        var a = Assignment()
        a.trigger = Trigger(kind: .key, code: 97)
        a.action = .shortcut
        a.outputKey = 8
        router.assignments = [a]
        key(0x05ac, 2, 0x3f, true)
        key(0x05ac, 2, 0x3f, false)
        check(
            events.isEmpty && actions.isEmpty,
            "Non-CHERRY keyboard cannot trigger mappings or synthesized passthrough")
        key(0x046a, 1, 0x3f, true)
        check(events.count == 1, "CHERRY key-down routed exactly once")
        check(
            events[0].getIntegerValueField(.keyboardEventKeycode) == 8
                && events[0].flags == .maskCommand, "Destination key and modifiers are fresh")
        check(
            events[0].getIntegerValueField(.eventSourceUserData) == syntheticMarker,
            "Relayed output is marked")
        key(0x046a, 1, 0x3f, true)
        check(events.count == 1, "Duplicate HID down ignored")
        router.assignments = []
        key(0x046a, 1, 0x3f, false)
        check(
            events.last!.type == .keyUp
                && events.last!.getIntegerValueField(.keyboardEventKeycode) == 8,
            "Release uses captured assignment across config changes")
        events = []
        a.action = .disable
        router.assignments = [a]
        key(0x046a, 1, 0x3f, true)
        key(0x046a, 1, 0x3f, false)
        check(events.isEmpty, "Disable suppresses only selected CHERRY trigger")
        key(0x05ac, 2, 0x3f, true)
        check(events.isEmpty, "Other keyboards still unaffected when disabled trigger exists")
        events = []
        key(0x046a, 1, 0x04, true)
        key(0x046a, 1, 0x04, false)
        check(
            events.count == 2 && events[0].getIntegerValueField(.keyboardEventKeycode) == 0,
            "Unassigned ordinary A passes through")
        events = []
        key(0x046a, 1, 0xe1, true)
        key(0x046a, 3, 0xe5, true)
        key(0x046a, 1, 0xe1, false)
        check(
            events.last!.flags.contains(.maskShift),
            "Modifier held on another CHERRY device survives release")
        key(0x046a, 3, 0xe5, false)
        check(!events.last!.flags.contains(.maskShift), "Last modifier release clears own state")
        events = []
        key(0x046a, 1, 0x3f, true, .maskCommand)
        key(0x046a, 1, 0x3f, false, .maskCommand)
        check(
            events.count == 2 && events[0].getIntegerValueField(.keyboardEventKeycode) == 97,
            "Modified trigger bypasses mapping")
        check(
            events[0].flags.contains(.maskCommand), "Modifier on an unseized keyboard is preserved")
        events = []
        a.action = .text
        a.value = "hello"
        router.assignments = [a]
        key(0x046a, 1, 0x3f, true)
        check(actions.isEmpty, "Text action waits for key release")
        key(0x046a, 1, 0x3f, false)
        check(actions.count == 1 && events.isEmpty, "CHERRY action runs on release")
        key(0x046a, 1, 0x3f, true)
        router.releaseDevice(1)
        check(actions.count == 1, "Disconnect cancels pending action")
        router.assignments = []
        events = []
        key(0x046a, 1, 0x04, true)
        key(0x046a, 1, 0xe0, true)
        router.releaseAll()
        check(
            events.contains {
                $0.type == .keyUp && $0.getIntegerValueField(.keyboardEventKeycode) == 0
            }, "Pause releases ordinary held key")
        check(
            events.last!.type == .flagsChanged && !events.last!.flags.contains(.maskControl),
            "Pause releases modifiers")
        events = []
        router.receive(
            vendor: 0x046a, device: 1, page: 12, usage: 0xcd, down: true, physicalFlags: [])
        router.receive(
            vendor: 0x046a, device: 1, page: 12, usage: 0xcd, down: false, physicalFlags: [])
        check(
            events.count == 2 && events[0].type.rawValue == 14,
            "Unassigned media control relays down and up")
        events = []
        a.trigger = Trigger(kind: .media, code: 16)
        a.action = .disable
        router.assignments = [a]
        router.receive(
            vendor: 0x046a, device: 1, page: 12, usage: 0xcd, down: true, physicalFlags: [])
        router.receive(
            vendor: 0x046a, device: 1, page: 12, usage: 0xcd, down: false, physicalFlags: [])
        check(events.isEmpty, "CHERRY media assignment suppresses native media behavior")
        key(0x046a, 1, 0xff, true)
        check(
            errors.count == 1,
            "Unknown HID key requests native-input recovery rather than global fallback")
        check(
            HIDKeyMap.keyboard[0x64] == 10 && HIDKeyMap.keyboard[0x89] == 93,
            "ISO and JIS translations are represented")
        router.releaseAll()
        events = []
        errors = []
        router.assignments = []
        key(0x046a, 1, 0x39, true)
        key(0x046a, 1, 0x39, false)
        key(0x046a, 1, 0x04, true, .maskAlphaShift)
        key(0x046a, 1, 0x04, false, .maskAlphaShift)
        key(0x046a, 1, 0x04, true, [])
        check(
            !events.last!.flags.contains(.maskAlphaShift),
            "Caps Lock on another keyboard supersedes local lock state")
        router.releaseAll()
        events = []
        a.trigger = Trigger(kind: .key, code: 97)
        a.action = .shortcut
        a.outputKey = 8
        var b = a
        b.id = UUID()
        b.trigger = Trigger(kind: .key, code: 98)
        router.assignments = [a, b]
        key(0x046a, 1, 0x3f, true)
        key(0x046a, 1, 0x40, true)
        key(0x046a, 1, 0x3f, false)
        check(
            !events.contains { $0.type == .keyUp },
            "Overlapping shortcuts do not release shared destination early")
        key(0x046a, 1, 0x40, false)
        check(events.last!.type == .keyUp, "Last shared destination releases")
        router.releaseAll()
        check(
            CaptureGate.decide(connected: false, secureInput: false, canPost: true, elapsed: 0)
                == .awaitHelper, "Start waits for the approved helper")
        check(
            CaptureGate.decide(connected: false, secureInput: true, canPost: true, elapsed: 2)
                == .awaitHelper,
            "Secure input while the helper connects cannot send a capture heartbeat")
        check(
            CaptureGate.decide(connected: true, secureInput: false, canPost: true, elapsed: 5)
                == .heartbeat, "Approved connected helper receives heartbeats")
        check(
            CaptureGate.decide(connected: true, secureInput: true, canPost: true, elapsed: 6)
                == .stopSecureEntry, "Secure input after capture starts restores native keyboard")
        check(
            CaptureGate.decide(connected: true, secureInput: false, canPost: false, elapsed: 7)
                == .stopPermissionLoss, "Output permission loss restores native keyboard")
        check(
            CaptureGate.decide(connected: false, secureInput: true, canPost: true, elapsed: 11)
                == .stopHelperTimeout, "Unresponsive managed-helper startup is bounded")
        router.releaseAll()
        events = []
        router.assignments = []
        var swap = Assignment()
        swap.trigger = Trigger(kind: .key, code: 58)
        swap.action = .modifier
        swap.outputKey = 55
        router.assignments = [swap]
        key(0x046a, 1, 0xe2, true)
        check(
            events.last!.getIntegerValueField(.keyboardEventKeycode) == 55
                && events.last!.flags.contains(.maskCommand)
                && !events.last!.flags.contains(.maskAlternate), "Physical Alt becomes held Command"
        )
        key(0x046a, 1, 0x06, true)
        key(0x046a, 1, 0x06, false)
        check(
            events.last!.flags.contains(.maskCommand),
            "Mapped Command applies to ordinary C shortcut")
        router.assignments = []
        key(0x046a, 1, 0xe2, false)
        check(
            events.last!.getIntegerValueField(.keyboardEventKeycode) == 55
                && !events.last!.flags.contains(.maskCommand),
            "Release preserves original mapping after profile edit")
        swap.trigger.code = 54
        swap.outputKey = 61
        router.assignments = [swap]
        events = []
        key(0x046a, 1, 0xe7, true)
        router.releaseAll()
        check(
            events.first!.getIntegerValueField(.keyboardEventKeycode) == 61
                && events.last!.flags.intersection(shortcutMask).isEmpty,
            "Right Windows becomes right Option and Pause releases it")
        events = []
        swap.trigger.code = 58
        swap.outputKey = 55
        router.assignments = [swap]
        key(0x05ac, 2, 0xe2, true)
        check(events.isEmpty, "Modifier remapping leaves non-CHERRY keyboards alone")
        key(0x046a, 1, 0xe2, true)
        key(0x046a, 3, 0xe2, true)
        key(0x046a, 1, 0xe2, false)
        check(
            events.last!.flags.contains(.maskCommand),
            "Shared mapped modifier remains held by the second device")
        key(0x046a, 3, 0xe2, false)
        check(
            !events.last!.flags.contains(.maskCommand),
            "Last mapped modifier release clears Command")
        router.releaseAll()
        router.releaseAll()
        router.assignments = []
        events = []
        key(0x046a, 1, 0x53, true)
        key(0x046a, 1, 0x53, true)
        check(!router.numLock && events.isEmpty, "Num Lock toggles once and does not emit Clear")
        key(0x046a, 1, 0x53, false)
        key(0x046a, 1, 0x5c, true)
        key(0x046a, 1, 0x5c, false)
        check(
            events.count == 2 && events.first!.getIntegerValueField(.keyboardEventKeycode) == 123,
            "Num Lock off relays keypad4 as Left")
        events = []
        key(0x046a, 1, 0x5d, true)
        key(0x046a, 1, 0x5d, false)
        check(events.isEmpty, "Navigation keypad5 is silent")
        key(0x046a, 1, 0x53, true)
        key(0x046a, 1, 0x53, false)
        key(0x046a, 1, 0x5c, true)
        key(0x046a, 1, 0x5c, false)
        check(
            router.numLock && events.first!.getIntegerValueField(.keyboardEventKeycode) == 86,
            "Num Lock on restores keypad4 numeric key")
        check(router.lockIndicators(physicalFlags: []).num, "Num indicator follows keypad state")
        router.releaseAll()
        key(0x046a, 1, 0x39, true)
        key(0x046a, 1, 0x39, false)
        check(
            router.lockIndicators(physicalFlags: []).caps,
            "Caps indicator follows relayed Caps Lock")
        check(
            router.lockIndicators(physicalFlags: .maskAlphaShift).caps,
            "Physical caps state is synchronized")
        check(
            !router.lockIndicators(physicalFlags: []).caps,
            "External caps change updates indicator without another CHERRY keystroke")
        router.releaseAll()
        router.releaseAll()
        router.assignments = []
        events = []
        key(0x0687, 9, 0x04, true)
        key(0x0687, 9, 0x04, false)
        check(
            events.count == 2 && events[0].getIntegerValueField(.keyboardEventKeycode) == 0,
            "Verified Bluetooth CHERRY input follows the normal relay path")
        print("PASS: \(checks) CHERRY-only HID routing checks. No devices opened or events posted.")
    }
}
