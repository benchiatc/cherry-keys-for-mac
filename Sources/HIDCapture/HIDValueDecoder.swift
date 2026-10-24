import IOKit.hid

struct HIDKeyState: Equatable {
    let page: UInt32
    let usage: UInt32
    let down: Bool
}

enum HIDValueDecoder {
    static func keyState(_ value: IOHIDValue) -> HIDKeyState? {
        let element = IOHIDValueGetElement(value)
        return keyState(
            type: IOHIDElementGetType(element), page: IOHIDElementGetUsagePage(element),
            usage: IOHIDElementGetUsage(element), isArray: IOHIDElementIsArray(element),
            integerValue: IOHIDValueGetIntegerValue(value))
    }
    static func keyState(
        type: IOHIDElementType, page: UInt32, usage: UInt32,
        isArray: Bool, integerValue: Int
    ) -> HIDKeyState? {
        guard
            type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Button
                || type == kIOHIDElementTypeInput_Axis || type == kIOHIDElementTypeInput_ScanCodes
        else { return nil }
        guard page != 0 else { return nil }
        // IOKit expands keyboard arrays into individual variable key elements.
        // It also delivers the array indices, identified by usage 0xffffffff.
        // Those are bookkeeping values, not additional keys. Ignore only an
        // actual array index; unknown variable usages still reach fail-open handling.
        guard !(usage == UInt32.max && isArray) else { return nil }
        return HIDKeyState(page: page, usage: usage, down: integerValue != 0)
    }
}
