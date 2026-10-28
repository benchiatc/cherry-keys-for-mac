# Changelog

Released previews are listed below. Version and build metadata come from `Resources/Info.plist`.

## 0.4.5 (build 16) — 2026-10-24

### Local rebuild refresh — 2026-10-28

- Rebuild the universal DMG from the existing app source with Apple Swift 6.1 on macOS 26.6.2; retain version 0.4.5/build 16 and the original release tag. No app source changes.
- Use a new local development signing identity. Existing installations may need fresh Accessibility, Input Monitoring and helper approval; remove the old helper before replacing the app.
- Pass all four automated test suites and verify that the mounted DMG and installed app match the fresh build byte-for-byte. No new physical keyboard acceptance is claimed.
- Refresh the DMG, source ZIP and checksums together; preserve the previous local DMG for rollback. This remains a development preview without Developer ID signing or notarization.

### Original release

- Handle KW X ULP Browser Home (`12/0x223`), Calculator (`12/0x192`) and Mail (`12/0x18A`) controls without pausing capture.
- Keep preset functions and standard F-keys independently assignable; label both layers and explain Ctrl+Fn/Fn Lock. Assignments do not inherit between layers.
- Preserve the selected profile across the receiver, both Bluetooth slots and wired USB. Add 78 transport-routing checks, including all 12 directed channel handoffs.
- Confirm independent F12 preset/standard mappings and Calculator physically over the F1 receiver. Browser Home sends Command–Shift–H; its visible browser behavior remains unverified.
- Retain the v0.4.4 privileged broker and capture helper.
- Refresh installation, architecture, hardware and security documentation; add a changelog and versioned setup guide.
- Add release consistency checks for README links, changelog, staged metadata, source ZIP content and checksums. Documentation/packaging refresh retains the same app version/build and keyboard behavior.

## 0.4.4 (build 13) — 2026-10-24

- Resume enabled remapping after sleep, session lock and temporary Secure Keyboard Entry interruptions. Explicit Pause remains paused.
- Add 10 recovery-policy checks and physically confirm sleep/wake and lock/unlock recovery.
- Publish a locally signed universal macOS preview, DMG, source ZIP and checksums.

## 0.4.3 (build 12) — pre-publication milestone

- Close the privileged executable-replacement race with a validated root-owned capture snapshot.
- Bound profile imports and payloads; preserve private settings and backups.
- Physically validate core typing, modifier mapping, Caps/Num behavior and LEDs across all four KW X ULP connection modes after helper hardening.

All published binaries remain development previews, without Apple Developer ID signing or notarization. See the [security review](docs/SECURITY-REVIEW.md) for scope and outstanding validation.
