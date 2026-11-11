@main
struct CaptureRecoveryTests {
    static func main() {
        var state = CaptureRecovery()
        func ready(_ state: CaptureRecovery, secure: Bool = false, console: Bool = true) -> Bool {
            state.canResume(secureInput: secure, onConsole: console)
        }
        precondition(!ready(state), "A fresh or manually paused app must not enable itself")
        state.observe(.sleep)
        state.suspend()
        precondition(!ready(state), "Suspended capture must not restart during sleep")
        state.observe(.resignSession)
        state.observe(.wake)
        precondition(!ready(state), "Wake alone must not resume a switched-out session")
        state.observe(.activateSession)
        precondition(!ready(state, secure: true), "Do not resume while secure input is active")
        precondition(!ready(state, console: false), "Do not capture another user's console")
        precondition(
            ready(state), "Enabled capture resumes after wake, active session and secure input end")
        state.cancel()
        state.observe(.wake)
        state.observe(.activateSession)
        precondition(!ready(state), "Manual Pause while waiting cancels the pending resume")
        state.suspend()
        state.cancel()
        precondition(!ready(state), "Editor/quit/failure Stop must cancel pending recovery")
        state.suspend()
        precondition(
            !ready(state, secure: true) && ready(state),
            "Secure-entry-only interruption recovers without workspace notifications")
        state.observe(.sleep)
        state.cancel()
        state.observe(.wake)
        precondition(!ready(state), "Sleep/wake must not override manual Stop")
        // EOF/heartbeat expiry can precede both sleep and session notifications.
        state = CaptureRecovery()
        state.suspend()
        precondition(
            ready(state), "Connection loss preserves intent without workspace notifications")
        state.observe(.resignSession)
        precondition(!ready(state), "Late lock notification blocks reconnect")
        state.observe(.sleep)
        state.observe(.wake)
        precondition(!ready(state), "Wake still waits for session activation")
        state.observe(.activateSession)
        precondition(ready(state), "Late notification ordering eventually resumes")
        state.cancel()
        precondition(!ready(state), "Manual Pause cancels connection-loss recovery")
        for message in [
            "The console user changed; native input restored.",
            "The GUI heartbeat expired; native input restored.",
            "The GUI heartbeat socket failed; native input restored.",
            "Four-hour capture limit reached; native input restored.",
        ] {
            precondition(CaptureRecovery.isTemporaryHelperStop(message))
        }
        for message in [
            "Invalid heartbeat command; native input restored.",
            "The GUI process identity changed.",
            "CHERRY interface includes unsupported input page 1; native input restored.",
            "Unknown capture failure",
        ] {
            precondition(!CaptureRecovery.isTemporaryHelperStop(message))
        }
        print(
            "PASS: 23 sleep/session/secure-input/manual-stop recovery checks. No OS events, input or hardware used."
        )
    }
}
