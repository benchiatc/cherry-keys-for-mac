import Foundation

/// USB uses CHERRY's USB vendor ID; BLE uses its Bluetooth company ID.
/// The Bluetooth exception is limited to the KW X ULP identity observed on hardware.
enum CherryDeviceIdentity {
    static let matching: [[String: Any]] = [
        ["VendorID": 0x046a],
        [
            "VendorID": 0x0687, "ProductID": 0xc113, "VendorIDSource": 1,
            "Product": "CHERRY KW X ULP", "Transport": "Bluetooth Low Energy",
        ],
    ]
    static func accepts(vendor: Int, product: Int, source: Int, name: String, transport: String)
        -> Bool
    {
        vendor == 0x046a
            || isKWXBluetooth(
                vendor: vendor, product: product, source: source, name: name, transport: transport)
    }
    static func isKWXBluetooth(
        vendor: Int, product: Int, source: Int, name: String, transport: String
    ) -> Bool {
        vendor == 0x0687 && product == 0xc113 && source == 1 && name == "CHERRY KW X ULP"
            && transport == "Bluetooth Low Energy"
    }
    // The helper validates the complete identity before sending any input.
    static func acceptsRelayVendor(_ vendor: Int) -> Bool { vendor == 0x046a || vendor == 0x0687 }
    static func isBluetoothAuxiliaryInput(page: UInt32, report: UInt32, verifiedKWXBluetooth: Bool)
        -> Bool
    {
        verifiedKWXBluetooth && page == 0xff00 && report == 0x11
    }
}
