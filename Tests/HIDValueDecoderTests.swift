import IOKit.hid

@main
struct HIDValueDecoderTests {
    static func decode(
        page: UInt32 = 7, usage: UInt32, array: Bool = false,
        type: IOHIDElementType = kIOHIDElementTypeInput_Button,
        value: Int = 1
    ) -> HIDKeyState? {
        HIDValueDecoder.keyState(
            type: type, page: page, usage: usage, isArray: array, integerValue: value)
    }
    static func main() {
        // Reproduce IOKit's documented array-index/expanded-key sequence.
        // Test metadata directly: CreateWithDictionary cannot manufacture the
        // special 0xffffffff array-index elements supplied by the HID kernel.
        let sequence = [
            decode(usage: UInt32.max, array: true, type: kIOHIDElementTypeInput_ScanCodes),
            decode(usage: 5),
            decode(
                usage: UInt32.max, array: true, type: kIOHIDElementTypeInput_ScanCodes, value: 0),
            decode(usage: 5, value: 0),
        ].compactMap { $0 }
        precondition(
            sequence == [
                HIDKeyState(page: 7, usage: 5, down: true),
                HIDKeyState(page: 7, usage: 5, down: false),
            ], "Array updates must not mask or duplicate B press/release")
        precondition(
            decode(usage: UInt32.max)?.usage == UInt32.max,
            "Unknown variable usage must still reach fail-open handling")
        precondition(
            decode(page: 12, usage: 0xcd) == HIDKeyState(page: 12, usage: 0xcd, down: true),
            "Consumer controls remain available")
        precondition(decode(usage: 0xe1)?.usage == 0xe1, "Modifier elements remain available")
        precondition(decode(page: 0, usage: 0) == nil, "Padding produces no key")
        precondition(
            decode(usage: 5, type: kIOHIDElementTypeOutput) == nil, "Output values produce no key")
        print("PASS: 6 HID value metadata regression checks. No devices opened or events posted.")
    }
}
