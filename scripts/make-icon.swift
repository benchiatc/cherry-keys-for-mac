import Foundation

// Convert the user-provided artwork into the standard macOS iconset sizes.
// Usage: swift scripts/make-icon.swift <output.iconset> [source.png]
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/AppIcon.png"
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            "-z", String(size * scale), String(size * scale), source, "--out",
            out.appendingPathComponent(name).path,
        ]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { fatalError("Icon conversion failed") }
    }
}
