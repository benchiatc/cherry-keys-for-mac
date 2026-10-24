# Security review — 2026-10-24

This is a source-focused engineering review, not an independent penetration test or proof of zero vulnerabilities. The current preview is **v0.4.5 build 16**. It retains the v0.4.5 routing behavior and the privileged broker/capture executables previously validated after the v0.4.3 hardening. Current release status and changes are recorded in the [changelog](../CHANGELOG.md).

## Findings and mitigations

| Finding | Mitigation | Evidence |
| --- | --- | --- |
| Root broker checked a user-writable executable before executing its original path, allowing replacement between verification and launch | Copy a no-follow regular-file descriptor into a root-owned private snapshot, bound size to 64 MiB, validate its embedded signature, execute only that snapshot and retain it until cleanup | Signed fixture survives original-file replacement; unsigned input and symlinks rejected; directory permissions and cleanup checked without root. Root snapshot launch and Pause/Enable cleanup also passed on the installed Mac |
| Profile imports read unbounded JSON; payload limits were incomplete | Bound JSON to 4 MiB, text to 64 KiB, profile names to 256 UTF-8 bytes and assignments to 1,000/profile; retain profile/macro limits | Oversized inputs rejected, original files preserved, validation/private-persistence tests pass |
| Investigation artifacts contained private host/device metadata and unrelated/vendor files | Keep them outside the public source tree; export an explicit allowlist without Git history, profiles, keys or device captures | Privacy check, extracted-archive inventory review and Gitleaks scans |
| Icon assets carried ancillary metadata | Strip PNG text/EXIF chunks, including embedded ICNS PNGs | Eight chunks removed without changing pixel data |
| Unsupported Consumer-page launch keys paused capture; temporary fallback merged the Fn layers | Recognize three allowlisted Consumer controls and keep their trigger namespace independent of standard F-keys | 93 key-routing and 78 transport-routing checks; independent preset/Fn behavior physically confirmed over F1 |
| Documentation, staged app and distribution could drift apart | Check source version/build, README links, changelog, staged metadata, source ZIP inventory/content and checksums; packaging rejects stale staged metadata | Release checks run locally and in CI; negative mismatch checks are part of release-tool validation |

## Trust boundaries reviewed

- Certificate/identifier pinning for both XPC peers, installed GUI path and active console-user validation.
- Root child snapshot verification; fixed executable, arguments and environment; no client-supplied executable path, script, profile or shell expression.
- Console UID, GUI PID/start-time/path, private socket ownership/mode and socket peer UID/PID checks.
- Bounded IPC buffers and profile data; watchdogs, stop handling, disconnect cleanup and suspended-input recovery.
- Device identity and collection allowlists; Caps/Num writes restricted to standard LED elements. No firmware/vendor-lighting writes.
- No app HTTP client/server, TCP listener, telemetry or automatic updater. IPC is local. Explicit file/application/website actions may invoke other apps; the unprivileged sleep action uses fixed `/usr/bin/pmset sleepnow` arguments.
- Default Mail resolves the local handler and opens the application without sending/composing a message. Consumer launch actions remain in the unprivileged GUI.

No third-party runtime libraries are bundled. macOS, the Swift runtime, build tools and user-launched applications remain external dependencies.

## Automated and artifact verification

- Gitleaks **8.30.1**, verified against upstream release checksums: source checkout and extracted source-export scans report no credential-pattern findings. This is not a general vulnerability assessment.
- The public-source audit checks allowlisted text for local account names, absolute user-home paths, device addresses and private-key material. Binary assets require separate review. No vendor installer, profile, raw device dump or signing material is exported.
- Universal GUI/broker/capture builds and model, router, transport, recovery, HID decoder, identity, argument/nonroot, helper setup, authenticated XPC and executable-snapshot tests pass. Tests do not register a service, seize hardware or post real input.
- CI uses an ephemeral signing identity. The signing wrapper temporarily includes its isolated keychain in the user search list and restores the original list; it does not change certificate trust or the default keychain. Password arguments/output are not logged by the wrapper.
- DMGs are mounted read-only for version/build, signature, payload and checksum verification. They contain the app, Applications shortcut, versioned setup guide, changelog and MIT license. Release checksums contain basenames, not build-machine paths.

## Physical acceptance and limits

| Version / scope | Confirmed | Still unverified |
| --- | --- | --- |
| v0.4.3 build 12, hardened helper | Root-owned signed snapshot startup, Pause/Enable without another password, cleanup and preserved profiles/permissions on one Mac | Disposable-account/clean-machine setup, reboot/crash behavior and full upgrade/removal matrix |
| v0.4.3 build 12, four modes | Core typing, modifier mapping, Caps/Num behavior and immediate LEDs on F1 receiver through a hub, F2, F3 and wired USB | Broader models/layouts/macOS/Intel hardware. Receiver remained enumerated during the later Bluetooth checks, so those do not establish unplugged-receiver isolation |
| v0.4.4 build 13 | Automatic recovery after sleep/wake and lock/unlock | Full adverse interruption matrix; protected password entry remains native |
| v0.4.5 build 16 | F1 preset F12 mapping and independent Fn + F12; Calculator | Latest layer checks physically repeated on F2/F3/wired USB; Browser Home visible behavior in specific browsers |
| v0.4.5 documentation/packaging refresh | Routing code, version/build and privileged executables retained | No additional hardware acceptance claimed |

The earlier “all transports predate hardening” limitation is resolved by the v0.4.3 checks above. Automated transport fixtures exercise normalized events and synthetic IDs; they do not prove radio timing or hardware report generation. Browser Home emits Command–Shift–H to the foreground app and may have no visible effect there.

## Remaining risks and production-release work

- Published DMGs are clearly labelled **locally signed development previews**, not Apple Developer ID signed or notarized. Protected production signing/notarization, clean-machine installation and broader compatibility validation remain outstanding. No security-control bypass is required or recommended.
- A source builder's local signing identity is accessible to that developer account. A process with access to that account/keychain may sign replacement code accepted by its local helper. This is not equivalent to a protected central production signing key.
- An already compromised administrator/root account or stolen signing key is outside the protection offered by certificate pinning and hardened runtime. Some macOS signing commands require a secret as a process argument; the scripts avoid logging those arguments.
- Self-reported device IDs can be spoofed. No firmware authentication or reliable cross-transport physical-unit serial identity has been established.
- Accessibility permits synthesized input. Unreviewed profiles can launch files/apps/URLs with user permissions; do not store secrets in macros.
- A broker crash may leave a root-only temporary executable snapshot containing signed program bytes. It contains no captured input or profiles; no broad background cleanup service is installed.
- Reboot, crash, repeated adverse reconnects, helper upgrade/removal and equivalent Intel hardware behavior need broader physical testing. Other CHERRY models remain unverified.

## Reproduce and report

```sh
python3 scripts/check-release.py
python3 scripts/prepare-local-signing.py
./scripts/build.sh
./scripts/test.sh
./scripts/test-input.sh
./scripts/test-capture.sh
./scripts/test-service.sh
xcrun swift-format lint --strict --recursive Sources Tests
python3 scripts/check-public-source.py
./scripts/package.sh
python3 scripts/export-source.py
python3 scripts/check-release.py --app ".build/package.noindex/Cherry Keys for Mac.app" --dist
# Extract the source ZIP, then run a trusted local Gitleaks installation:
gitleaks dir /path/to/extracted/CherryKeysMac --redact
```

Scan any history that will be published, keep raw reports private, and share only reviewed/redacted evidence. Report vulnerabilities through the [private reporting form](https://github.com/benchiatc/cherry-keys-for-mac/security/advisories/new). No scanner or reviewer can guarantee that the software is unexploitable.
