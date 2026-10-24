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
        print(
            "PASS: 10 sleep/session/secure-input/manual-stop recovery checks. No OS events, input or hardware used."
        )
    }
}
