# Architecture

## Processes and trust boundaries

| Component | Privilege | Responsibility |
| --- | --- | --- |
| `CherryKeysMac` | Logged-in user, Accessibility/Input Monitoring | SwiftUI, private profiles, HID routing, synthesized actions and mouse modifier event tap |
| `CherryKeysCaptureService` | Root, approved SMAppService | Authenticates XPC clients and launches only the capture child |
| `CherryKeysHIDCapture` | Root, bounded session | Exclusive access to verified CHERRY interfaces, source-tagged input, standard Caps/Num LED output |

The broker does not receive profiles, arbitrary commands or executable paths. XPC peers must satisfy a certificate-and-identifier requirement and be the installed GUI for the current console user. The GUI authenticates the broker too. These checks use Security.framework and NSXPC's code-signing requirements.

The broker snapshots the fixed capture executable into a private temporary directory, verifies that snapshot's embedded signature against its own signing certificate and the capture identifier, and launches that protected snapshot. This avoids checking a user-writable file and subsequently executing a replacement. Root-private snapshots are removed when a session is stopped/replaced or the broker exits normally; a broker crash can leave a root-only temporary directory. The broker never executes scripts or interpolates shell commands.

The child verifies console UID, GUI path, PID/start time, private directory ownership/mode, socket ownership/mode, and the socket's UID/PID peer. It waits for an authenticated local heartbeat before discovery. Input is newline-delimited JSON over a Unix-domain socket, not TCP. The GUI bounds the input queue. The return channel accepts only stop, heartbeat and the four two-bit lock states; unknown bytes stop capture.

Only CHERRY keyboard and associated consumer-control interfaces are seized. Unsupported input fails back to native handling. A narrowly scoped exception ignores the verified KW X ULP BLE vendor input report; no vendor control or feature-report writes occur. Standard Caps/Num output elements are committed together.

## Lifecycle and state

`HIDRouter` indexes held keys/modifiers by device registry identity and HID usage. Disconnect releases that device's synthesized state. Pause/Quit release all state and stop capture. `CaptureRecovery` retains enabled intent across temporary sleep/session/secure-input interruptions, with workspace observers that remain registered while capture is stopped and a 500ms recovery timer. Resume requires no active secure input and an active console session. Explicit Stop and permanent errors cancel pending recovery; macros are cancelled rather than replayed. Action execution occurs in the GUI, with cancellation for macros. A socket read source delivers lock changes immediately; timers maintain liveness and synchronize external lock changes. Missed heartbeats expire after two seconds; capture has a four-hour ceiling.

`ConfigurationStore` validates bounded JSON, saves atomically, restricts settings-directory permissions and retains one private backup. Profiles are user-owned settings, never inputs to the root broker. The active profile applies to all captured devices; there is no physical-unit profile enrollment.

## Mouse modifier propagation

Seizing the CHERRY keyboard prevents its physical modifier state from reaching native mouse events. Synthesizing a Shift keyboard event alone does not ensure that a later native click carries Shift. `HIDRouter.pointerFlags` unions each currently held CHERRY modifier output into the incoming mouse event flags. It uses mapped outputs, excludes disabled modifiers and preserves the live native flags, including modifiers from other keyboards. It does not reuse `baseFlags`, which is a keyboard-time snapshot that could retain an externally released modifier.

`InputEngine` installs an active `cgSessionEventTap` at the head of the session event stream before starting capture. It covers left/right/other button down/up, movement, dragging and wheel scrolling. Events pass through with their flags updated in place; mouse buttons, coordinates and scrolling are not remapped or suppressed. The callback and HID routing run on the main run loop. macOS timeout/user-input tap disable notifications re-enable the tap while the engine is running. Failure to create the tap aborts startup and restores native input.

Held modifier state follows the existing per-device release rules. Disconnect clears only the removed device; overlapping modifiers from another captured device remain held. Pause, Quit and temporary suspension remove the tap and release all state; automatic recovery creates a fresh tap. The GUI uses its existing Accessibility approval, and no mouse processing is added to the root broker or capture child.

Twelve injected-event regressions cover Shift, overlapping devices, mapped/disabled modifiers, native flag preservation, stale keyboard snapshots and cleanup. They do not install a real event tap or exercise native pointer delivery. TradingView Shift-click was physically confirmed on F1 in local v0.4.5 build 17; v0.4.6 build 18 retains the same implementation.

## Trigger resolution and transport consistency

| Trigger namespace | Input | Resolution |
| --- | --- | --- |
| `key` | HID keyboard page 7 | Standard key or F-key assignment; otherwise normal key relay |
| `media` | Known Consumer-page media usages | NX media assignment; otherwise media relay |
| `consumer` | Browser Home, Calculator, Mail usages | Explicit preset assignment; otherwise the documented preset default |

Trigger lookup uses kind/code from the selected profile, not a port, Bluetooth slot or registry ID. There is no inheritance between standard F-key and consumer-preset assignments. The UI's Fn labels describe the KW X ULP Fn-light-off arrangement; hardware Fn Lock changes the HID event produced, and the app routes that event without trying to observe the Fn light. Unknown keys restore native input rather than being silently discarded. Launch defaults execute in the unprivileged GUI; Mail resolves the local default mail handler without composing a message.

`TransportRoutingTests` covers split USB interfaces and combined Bluetooth interfaces, profile consistency and independent layers across four synthetic connection fixtures, plus all 12 directed channel handoffs. Device identity remains part of held-state tracking so late releases from an old channel cannot complete a cancelled action on the new one. These tests do not establish radio timing or hardware report generation.

## Source layout

- `Sources/Shared`: XPC contract, signing requirement and device identity policy.
- `Sources/CaptureService`: root broker and validated executable snapshot.
- `Sources/HIDCapture`: bounded HID acquisition, input decoding and LED writes.
- `Sources/CherryKeysMac`: UI, model, router, action runner and unprivileged socket client.
- `Tests`: injected-event routing tests, validation/storage tests and nonprivileged IPC/snapshot checks.

Tests do not prove that macOS approval, HID capture, LEDs, transport reconnection or secure input behave correctly on every machine. Hardware acceptance is separate.

## Connection-loss recovery (v0.4.7 build 20)

Helper EOF, socket/heartbeat interruption and XPC interruption preserve enabled intent and release capture before reconnecting. Known console-session, heartbeat-expiry and bounded-session stops also recover; other helper errors, validation failures, unsupported input and explicit Pause remain permanent stops. This covers helper failure arriving before workspace notifications. A fresh capture session revalidates permissions, signing and console identity; secure input remains native. A secure-input race during resume waits again rather than clearing user intent. The user reports F1 recovery working after installation; the separate cycle/manual-Pause checklist remains unconfirmed.

While capture runs, a user-session event tap merges held CHERRY modifier outputs into native mouse clicks, movement, drags and scrolling. Native flags are preserved; the tap is removed on stop. This retains the locally verified Shift-click fix while restoring recovery.
