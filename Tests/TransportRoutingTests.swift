import AppKit
import IOKit.hid

/// Synthetic registry IDs and normalized HID elements, not captured device reports.
/// USB has separate keyboard/consumer interfaces; each Bluetooth slot combines them.
private struct Channel {
    let name: String
    let vendor: Int
    let product: Int
    let source: Int
    let model: String
    let transport: String
    let keyboard: UInt64
    let consumer: UInt64

    static let all: [Channel] = [
        Channel(
            name: "F1 receiver", vendor: 0x046a, product: 0xc111, source: 0,
            model: "CHERRY Wireless Device", transport: "USB", keyboard: 10, consumer: 11),
        Channel(
            name: "F2 Bluetooth", vendor: 0x0687, product: 0xc113, source: 1,
            model: "CHERRY KW X ULP", transport: "Bluetooth Low Energy", keyboard: 20, consumer: 20),
        Channel(
            name: "F3 Bluetooth", vendor: 0x0687, product: 0xc113, source: 1,
            model: "CHERRY KW X ULP", transport: "Bluetooth Low Energy", keyboard: 30, consumer: 30),
        Channel(
            name: "Wired USB", vendor: 0x046a, product: 0xc112, source: 0,
            model: "CHERRY Corded Keyboard", transport: "USB", keyboard: 40, consumer: 41),
    ]
}

@main
struct TransportRoutingTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
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
        func send(_ channel: Channel, _ page: UInt32, _ usage: UInt32, _ down: Bool) {
            guard
                let state = HIDValueDecoder.keyState(
                    type: kIOHIDElementTypeInput_Button, page: page, usage: usage,
                    isArray: false, integerValue: down ? 1 : 0)
            else { preconditionFailure("Normalized key was lost in the decoder") }
            router.receive(
                vendor: channel.vendor, device: page == 12 ? channel.consumer : channel.keyboard,
                page: state.page, usage: state.usage, down: state.down, physicalFlags: [])
        }
        func release(_ channel: Channel) {
            router.releaseDevice(channel.keyboard)
            if channel.consumer != channel.keyboard { router.releaseDevice(channel.consumer) }
        }
        func mapping(_ kind: Trigger.Kind, _ code: Int, _ text: String) -> Assignment {
            var result = Assignment()
            result.trigger = Trigger(kind: kind, code: code)
            result.action = .text
            result.value = text
            return result
        }
        let preset = mapping(.consumer, 0x18a, "preset layer")
        let standard = mapping(.key, 111, "standard layer")
        let profile = Profile(name: "Shared profile", assignments: [preset, standard])
        router.assignments = profile.assignments
        for channel in Channel.all {
            check(
                CherryDeviceIdentity.accepts(
                    vendor: channel.vendor, product: channel.product, source: channel.source,
                    name: channel.model, transport: channel.transport),
                "Known identity rejected: \(channel.name)")
            actions = []
            events = []
            send(channel, 12, 0x18a, true)
            send(channel, 12, 0x18a, true)
            send(channel, 12, 0x18a, false)
            send(channel, 12, 0x18a, false)
            check(actions == [preset], "Same preset mapping must execute once on every channel")
            actions = []
            send(channel, 7, 0x45, true)
            send(channel, 7, 0x45, false)
            check(actions == [standard], "Fn layer must remain independent on every channel")
            for usage: UInt32 in [0x223, 0x192] {
                actions = []
                send(channel, 12, usage, true)
                send(channel, 12, usage, false)
                let expected = ConsumerControl(rawValue: Int(usage))!.defaultAssignment
                check(
                    actions.count == 1 && actions[0].trigger == expected.trigger
                        && actions[0].action == expected.action
                        && actions[0].value == expected.value
                        && actions[0].outputKey == expected.outputKey
                        && actions[0].modifiers == expected.modifiers,
                    "Unassigned preset defaults must match across channels")
            }
            actions = []
            send(channel, 12, 0xcd, true)
            send(channel, 12, 0xcd, false)
            check(
                events.count == 2 && events.allSatisfy { $0.type.rawValue == 14 },
                "Media passthrough must work on split and combined interfaces")
            events = []
            send(channel, 7, 0x04, true)
            send(channel, 7, 0x04, false)
            check(
                events.count == 2 && events[0].type == .keyDown && events[1].type == .keyUp
                    && events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 0 },
                "Ordinary typing must be independent of transport")
            check(
                router.assignments == profile.assignments, "Transport must not rewrite the profile")
            check(errors.isEmpty, "Supported controls must not pause capture")
            release(channel)
        }

        // Every directed channel transition: old key releases cannot run a cancelled
        // action or release a new device's press, even when both send the same usage.
        for source in Channel.all {
            for destination in Channel.all where source.name != destination.name {
                actions = []
                send(source, 12, 0x18a, true)
                release(source)
                send(destination, 12, 0x18a, true)
                send(source, 12, 0x18a, false)
                check(
                    actions.isEmpty,
                    "Channel handoff cancels held actions and ignores stale releases")
                send(destination, 12, 0x18a, false)
                check(actions == [preset], "New channel must retain the same preset assignment")
                actions = []
                send(source, 7, 0x45, true)
                release(source)
                send(destination, 7, 0x45, true)
                send(destination, 7, 0x45, false)
                check(
                    actions == [standard], "New channel must retain the independent Fn assignment")
                release(destination)
            }
        }

        let second = mapping(.consumer, 0x18a, "second profile")
        router.assignments = [second]
        for channel in Channel.all {
            actions = []
            send(channel, 12, 0x18a, true)
            send(channel, 12, 0x18a, false)
            check(actions == [second], "A newly selected profile must apply on every channel")
        }
        actions = []
        events = []
        for page: UInt32 in [7, 12] {
            for down in [true, false] {
                router.receive(
                    vendor: 0x046d, device: 50, page: page, usage: page == 12 ? 0x18a : 0x45,
                    down: down, physicalFlags: [])
            }
        }
        check(events.isEmpty && actions.isEmpty, "Other brands must remain unaffected")
        check(errors.isEmpty, "Channel switching must not trigger unsupported-key recovery")
        router.releaseAll()
        print(
            "PASS: \(checks) transport routing checks across four synthetic channels and all 12 directed handoffs. No devices opened or events posted."
        )
    }
}
