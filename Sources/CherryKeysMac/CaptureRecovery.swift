/// User intent survives temporary OS interruptions, but never an explicit Stop
/// or a permanent capture failure. The engine owns all OS I/O and retry timing.
struct CaptureRecovery {
    enum Event { case sleep, wake, resignSession, activateSession }
    private(set) var waiting = false
    private var sleeping = false
    private var activeSession = true

    mutating func observe(_ event: Event) {
        switch event {
        case .sleep: sleeping = true
        case .wake: sleeping = false
        case .resignSession: activeSession = false
        case .activateSession: activeSession = true
        }
    }
    /// The bounded helper may stop before workspace notifications arrive.
    /// Only known lifecycle stops recover; validation/protocol failures remain permanent.
    static func isTemporaryHelperStop(_ message: String) -> Bool {
        [
            "The console user changed; native input restored.",
            "The GUI heartbeat expired; native input restored.",
            "The GUI heartbeat socket failed; native input restored.",
            "Four-hour capture limit reached; native input restored.",
        ].contains(message)
    }
    mutating func suspend() { waiting = true }
    mutating func cancel() { waiting = false }
    func canResume(secureInput: Bool, onConsole: Bool) -> Bool {
        waiting && !sleeping && activeSession && !secureInput && onConsole
    }
}
