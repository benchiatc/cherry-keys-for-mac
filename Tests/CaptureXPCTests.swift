import Foundation

private final class FakeService: NSObject, CherryCaptureServiceProtocol {
    func startCapture(directory: String, withReply reply: @escaping (String?) -> Void) {
        reply(CaptureServiceInfo.validSocketDirectory(directory) ? nil : "Invalid directory")
    }
}
private final class Delegate: NSObject, NSXPCListenerDelegate {
    var clients: [NSXPCConnection] = []
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        connection.exportedObject = FakeService()
        connection.exportedInterface = NSXPCInterface(with: CherryCaptureServiceProtocol.self)
        clients.append(connection)
        connection.resume()
        return true
    }
}
@main
struct CaptureXPCTests {
    static func main() throws {
        let identity = try CaptureServiceInfo.requirement(
            identifier: "local.cherrykeys.mac.tests.xpc")
        let listener = NSXPCListener.anonymous()
        let delegate = Delegate()
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(identity)
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.setCodeSigningRequirement(identity)
        connection.remoteObjectInterface = NSXPCInterface(with: CherryCaptureServiceProtocol.self)
        connection.resume()
        defer {
            connection.invalidate()
            for c in delegate.clients { c.invalidate() }
            listener.invalidate()
        }
        for path in ["/private/tmp/ckm-" + UUID().uuidString, "/etc/passwd"] {
            var completed = false
            var failure: String?
            let proxy =
                connection.remoteObjectProxyWithErrorHandler { error in
                    failure = error.localizedDescription
                    completed = true
                } as! CherryCaptureServiceProtocol
            proxy.startCapture(directory: path) { error in
                if CaptureServiceInfo.validSocketDirectory(path) {
                    failure = error
                } else if error != "Invalid directory" {
                    failure = "Expected rejection"
                }
                completed = true
            }
            let deadline = Date().addingTimeInterval(3)
            while !completed && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(
                completed && failure == nil,
                "Certificate-authenticated XPC round trip failed: \(failure ?? "timeout")")
        }
        print(
            "PASS: authenticated XPC protocol round trips encode success and rejection. Anonymous local listener only; no privileged service or hardware used."
        )
    }
}
