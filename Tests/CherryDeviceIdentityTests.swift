import Foundation

@main
struct CherryDeviceIdentityTests {
    static func main() {
        func accepts(
            _ vendor: Int = 0x0687, _ product: Int = 0xc113, _ source: Int = 1,
            _ name: String = "CHERRY KW X ULP", _ transport: String = "Bluetooth Low Energy"
        ) -> Bool {
            CherryDeviceIdentity.accepts(
                vendor: vendor, product: product, source: source, name: name, transport: transport)
        }
        precondition(accepts())
        precondition(accepts(0x046a, 0xc111, 0, "CHERRY Wireless Device", "USB"))
        precondition(!accepts(0x05ac))
        precondition(!accepts(0x0687, 0xc112))
        precondition(!accepts(0x0687, 0xc113, 2))
        precondition(!accepts(0x0687, 0xc113, 1, "Another keyboard"))
        precondition(!accepts(0x0687, 0xc113, 1, "CHERRY KW X ULP", "USB"))
        precondition(
            CherryDeviceIdentity.isBluetoothAuxiliaryInput(
                page: 0xff00, report: 0x11, verifiedKWXBluetooth: true))
        precondition(
            !CherryDeviceIdentity.isBluetoothAuxiliaryInput(
                page: 0xff00, report: 0x11, verifiedKWXBluetooth: false))
        precondition(
            !CherryDeviceIdentity.isBluetoothAuxiliaryInput(
                page: 0xff01, report: 0x11, verifiedKWXBluetooth: true))
        precondition(
            !CherryDeviceIdentity.isBluetoothAuxiliaryInput(
                page: 0xff00, report: 0x12, verifiedKWXBluetooth: true))
        precondition(
            !CherryDeviceIdentity.isBluetoothAuxiliaryInput(
                page: 7, report: 1, verifiedKWXBluetooth: true))
        print(
            "PASS: 12 CHERRY transport identity and auxiliary-report boundary checks. No devices opened."
        )
    }
}
