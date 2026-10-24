# Source security review — 2026-10-24

This is a source-focused engineering review, not an independent penetration test or a claim of zero vulnerabilities. Earlier hardware acceptance covered the pre-hardening build. Version 0.4.3 build12 has now passed root broker/snapshot startup and Pause/Enable lifecycle checks on one Mac; wired physical-key acceptance also passed. Do not call the new binary production certified.

## Findings and changes

| Finding | Change | Verification |
| --- | --- | --- |
| Root broker validated a user-writable executable before executing its original path, allowing a replacement race | Copy from a no-follow regular-file descriptor, bound size to 64 MiB, validate the protected snapshot, execute only that snapshot, and retain it until session cleanup | Signed fixture survives replacement of original; unsigned input/symlinks rejected; private directory permissions and cleanup checked without root |
| Profile imports read unbounded JSON; assignment sizes/counts were incompletely bounded | Bound JSON reads/saves to 4 MiB, text to 64 KiB, profile names to 256 UTF-8 bytes, assignments to 1,000/profile; retain existing 100-profile and macro limits | Oversized imports/payloads rejected; original file preserved; existing persistence/validation regressions pass |
| Troubleshooting directory contained host/device metadata and unrelated/vendor artifacts | Move private artifacts out of source; replace investigation logs with generic contributor documentation; source export uses explicit allowlist and excludes Git history | Export privacy check, archive inventory review and Gitleaks scan |
| Icon assets contained ancillary metadata | Strip PNG text/EXIF chunks, including PNGs embedded in ICNS | Eight metadata chunks removed without changing pixel data |

## Checks performed

- Gitleaks **8.30.1**, upstream binary checksum verified against its published release checksums: directory scan of the extracted source-only export, redacted report, **no findings**. This is credential-pattern scanning, not a full vulnerability assessment.
- Public-source check: no detected local account name, absolute user-home paths, Bluetooth/MAC addresses or private-key material in allowlisted text. Binary assets reviewed separately. No vendor MSI, extracted binaries, device snapshots, profiles, local certificates, keys or keychain passwords are exported.
- Manual review of XPC certificate/identifier pinning, console-user/PID/path validation, socket ownership/peer checks, fixed child arguments/environment, watchdog/stop handling, HID identity/collection limits and LED write scope.
- Release checksums now use archive basenames rather than absolute build paths. Built GUI/broker/capture binaries were also checked for the local account string; none was present.
- Source search found no network transport API, TCP listener, dynamic library loading or shell-command evaluation in app code. One fixed `/usr/bin/pmset sleepnow` child remains in the unprivileged action runner. Explicit launch/URL actions invoke the user's chosen applications.
- Universal capture, broker and GUI compile with the local Apple SDK. Formatting lint and model, router, decoder, identity, argument/nonroot, helper setup, authenticated XPC and executable snapshot tests pass. Tests never register a service or open hardware.
- No third-party runtime libraries or package-manager dependencies are bundled. This does not rule out vulnerabilities in macOS, Swift runtime, build tools or dependencies of applications invoked by assignments.

## Remaining release gates and limitations

- Test the changed root broker's snapshot launch with real HID capture and macOS approvals on a disposable machine/account, including restart, helper upgrade/removal, crash and interruption handling. Unit tests cannot establish TCC/SMAppService behavior.
- Validate all hardware transports after privileged-path changes. Existing manual KW X ULP results predate the snapshot hardening.
- Establish Developer ID signing/notarization and clean-machine installation/upgrade checks before distributing public binaries. Local self-signing is for source builders; private keys must stay private.
- Device IDs can be spoofed. No firmware authentication or shared cross-transport serial identity is established.
- Accessibility-enabled applications can synthesize input. Imported mappings can launch files/programs or open URLs as the user. Do not import unreviewed profiles or store secrets in macros.
- A local development signing identity is accessible to its developer account. A malicious process with access to that account/keychain may be able to sign replacement code satisfying the helper requirement. Do not treat source-builder signing as equivalent to a centrally protected production signing key; public releases need a separately controlled signing pipeline.
- Hardened runtime and certificate pinning do not defend against an already compromised administrator/root account or stolen signing key. Signing-tool passwords are local secrets, and some macOS `security` commands require them as process arguments; no logging of those arguments is added.
- A crash can leave a root-only executable snapshot under the system temporary directory. It contains signed program bytes, not captured input or settings. No background broad cleanup job is added.
- The working project was untracked within a parent Git repository. The export intentionally excludes all history; if publishing existing history instead, scan that full history independently.

## Reproduce

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-input.sh
./scripts/test-capture.sh
./scripts/test-service.sh
xcrun swift-format lint --strict --recursive Sources Tests
python3 scripts/check-public-source.py
python3 scripts/export-source.py
# Extract the source ZIP, then run a trusted local Gitleaks installation:
gitleaks dir /path/to/extracted/CherryKeysMac --redact
```

Preserve private scanner output locally; only share redacted, reviewed reports. No scanner or reviewer can guarantee that software is unexploitable.

## Installed upgrade validation — 0.4.3 build12

The existing helper was unregistered before installation. The app and all installed executable bytes match the signed staged build; profiles were unchanged and a private rollback copy was retained. Initial launch was rejected by a macOS launch constraint after replacing the bundle. Refreshing LaunchServices registration and unregistering/registering the helper again resolved that error without disabling any security controls or changing its signing identity.

The new broker launched the signed capture snapshot as root inside a root-owned mode0700 directory. The GUI reached CHERRY capture active over wired USB. Pause stopped capture and removed the snapshot directory; re-enabling created a new protected snapshot and returned to capture active without a password. Accessibility/Input Monitoring and existing assignments were retained. The user confirmed typing, Alt+A modifier remapping, Caps Lock behavior/LED and Num Lock/keypad behavior/LED all work on wired USB, with immediate LED feedback. All four transport modes were subsequently rechecked below. Crash, reboot and clean-machine acceptance remain release gates.

### F1 receiver via USB hub — upgraded build acceptance

On v0.4.3 build12, the receiver was observed as USB046A:C111 with keyboard and consumer interfaces after wired USB was disconnected. The upgraded root snapshot capture restarted successfully without a password. The user confirmed typing, Alt+A modifier mapping, Caps behavior/LED and Num keypad behavior/LED all work with immediate LED feedback through a USB hub. Bluetooth F2/F3 results follow below.

### F2 Bluetooth — upgraded build acceptance

On v0.4.3 build12, the user selected F2 and confirmed all works. IORegistry and GUI show CHERRY KW X ULP BLE0687:C113 with source1, and capture active in the upgraded root snapshot process. The USB receiver was also still enumerated, so this was not a receiver-unplugged isolation test. F3 results follow below.

### F3 Bluetooth and completed connector checks — upgraded build

The user selected F3 and confirmed all works in response to the typing, Alt+A, Caps/Num behavior and LED checklist. The observed Bluetooth connection identity changed from F2 to F3 while the model/report descriptor stayed the same. The root capture snapshot process remained running across the change. The receiver remained enumerated during Bluetooth checks, so these results do not claim receiver-unplugged isolation.

All four connection modes have now passed the guided core-function checks on v0.4.3 build12: wired USB, F1 receiver through a USB hub, F2 Bluetooth and F3 Bluetooth. This covers the changed root snapshot launch path with actual input/LED acceptance. These are one keyboard/one Mac results, not a full OS/hardware compatibility matrix. Complete media coverage, adverse reconnects, crash behavior, clean-machine setup, reboot, public signing and notarization remain separate release work.

## Sleep/session recovery fix — 0.4.4 build13

The previous engine permanently paused on sleep/session or secure-input interruption because its stop path removed observers and cleared the UI enabled state. A separate recovery policy now preserves intent only for temporary OS interruptions. Persistent workspace observers and a 500ms secure-input/console gate resume capture after the interruption. Explicit Pause, editor stop, Quit, permission loss and permanent capture failures cancel recovery. No privileged helper, trust check or secure-input bypass was changed. Ten recovery sequence regressions and the existing47 routing checks passed; universal GUI compiled and installed with matching signatures and settings preserved. The user physically confirmed automatic resumption after both sleep/wake and lock/unlock. The computer-control service was unavailable during installation; reopening was handed to the user.

## Clean-runner signing compatibility

The first macOS15 CI run exposed a signing lookup failure despite the isolated identity being present. Build and signed-test steps now use a shared local signing wrapper that temporarily includes the isolated keychain in the user search list and restores the previous list afterward. No certificate trust or default-keychain policy is modified. Signing calls are serialized, passwords are not logged, and local verification confirmed exact restoration of the original search list. The clean macOS runner subsequently completed the universal app build/signing stage; the automated tests remain separate from physical keyboard acceptance.
