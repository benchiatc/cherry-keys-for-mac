# Architecture

## Processes and trust boundaries

| Component | Privilege | Responsibility |
| --- | --- | --- |
| `CherryKeysMac` | Logged-in user, Accessibility/Input Monitoring | SwiftUI, private profiles, HID routing and synthesized actions |
| `CherryKeysCaptureService` | Root, approved SMAppService | Authenticates XPC clients and launches only the capture child |
| `CherryKeysHIDCapture` | Root, bounded session | Exclusive access to verified CHERRY interfaces, source-tagged input, standard Caps/Num LED output |

The broker does not receive profiles, arbitrary commands or executable paths. XPC peers must satisfy a certificate-and-identifier requirement and be the installed GUI for the current console user. The GUI authenticates the broker too. These checks use Security.framework and NSXPC's code-signing requirements.

The broker snapshots the fixed capture executable into a private temporary directory, verifies that snapshot's embedded signature against its own signing certificate and the capture identifier, and launches that protected snapshot. This avoids checking a user-writable file and subsequently executing a replacement. Root-private snapshots are removed when a session is stopped/replaced or the broker exits normally; a broker crash can leave a root-only temporary directory. The broker never executes scripts or interpolates shell commands.

The child verifies console UID, GUI path, PID/start time, private directory ownership/mode, socket ownership/mode, and the socket's UID/PID peer. It waits for an authenticated local heartbeat before discovery. Input is newline-delimited JSON over a Unix-domain socket, not TCP. The GUI bounds the input queue. The return channel accepts only stop, heartbeat and the four two-bit lock states; unknown bytes stop capture.

Only CHERRY keyboard and associated consumer-control interfaces are seized. Unsupported input fails back to native handling. A narrowly scoped exception ignores the verified KW X ULP BLE vendor input report; no vendor control or feature-report writes occur. Standard Caps/Num output elements are committed together.

## Lifecycle and state

`HIDRouter` indexes held keys/modifiers by device registry identity and HID usage. Disconnect releases that device's synthesized state. Pause/Quit release all state and stop capture. `CaptureRecovery` retains enabled intent across temporary sleep/session/secure-input interruptions, with workspace observers that remain registered while capture is stopped and a 500ms recovery timer. Resume requires no active secure input and an active console session. Explicit Stop and permanent errors cancel pending recovery; macros are cancelled rather than replayed. Action execution occurs in the GUI, with cancellation for macros. A socket read source delivers lock changes immediately; timers maintain liveness and synchronize external lock changes. Missed heartbeats expire after two seconds; capture has a four-hour ceiling.

`ConfigurationStore` validates bounded JSON, saves atomically, restricts settings-directory permissions and retains one private backup. Profiles are user-owned settings, never inputs to the root broker. The active profile applies to all captured devices; there is no physical-unit profile enrollment.

## Source layout

- `Sources/Shared`: XPC contract, signing requirement and device identity policy.
- `Sources/CaptureService`: root broker and validated executable snapshot.
- `Sources/HIDCapture`: bounded HID acquisition, input decoding and LED writes.
- `Sources/CherryKeysMac`: UI, model, router, action runner and unprivileged socket client.
- `Tests`: injected-event routing tests, validation/storage tests and nonprivileged IPC/snapshot checks.

Tests do not prove that macOS approval, HID capture, LEDs, transport reconnection or secure input behave correctly on every machine. Hardware acceptance is separate.
