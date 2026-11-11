# Changelog

Release candidates, local fixes and released previews are listed below. Version and build metadata come from `Resources/Info.plist`.

## 0.4.7 (build 20) — 2026-11-11

- Recover from capture connection loss, interrupted XPC and known helper lifecycle stops even when they arrive before sleep/lock notifications.
- Preserve manual Pause and permanent validation/protocol failure behavior; handle secure input becoming active during resume.
- Retain modifier + mouse support from the installed local build. Add recovery regressions; 23 recovery checks pass. The user reports F1 recovery working after installation; individual sleep/lock cycles and manual-Pause behavior were not separately confirmed.
- Privileged capture and broker executables remain unchanged.


## 0.4.6 (build 18) — 2026-11-06

- Restore modifier + mouse shortcuts while remapping is active, including TradingView's Shift-click ruler. Merge held CHERRY modifier outputs into native clicks, movement, drags and scrolling, preserving native flags from other keyboards.
- Support mapped modifier outputs and disabled modifiers; clear held state on release, disconnect and Pause, and remove the event tap on stop. All mouse handling stays in the unprivileged GUI.
- Physically confirm the TradingView ruler on the F1 receiver in local v0.4.5 build 17. Build 18 retains that implementation with updated release metadata. Other transports and mouse combinations still need physical acceptance.
- Pass 105 key-routing checks (including 12 mouse-modifier regressions), 78 transport-routing checks and 10 recovery checks, plus model, decoder, identity, helper and IPC/snapshot suites.
- Retain the installed privileged broker and capture helper byte-for-byte. Existing profiles remain compatible. Release this fix separately as v0.4.6; v0.4.5 downloads remain build 16.

### Installation guide refresh — 2026-11-06

- Expand the README into an illustrated 11-step DMG setup guide, including first-open security prompts, both separate permissions, missing-entry addition, full quit/reopen, background helper approval and final working-state checks.
- Add annotated screenshots with private/unrelated content excluded and clearly identify first-run UI previews and macOS naming differences.
- Bundle the same guide as offline HTML with its screenshots, generated from the README, and expand the installer quick-start checklist. This documentation/packaging update keeps v0.4.6 build 18 and app behavior unchanged.

## 0.4.5 (build 17) — 2026-11-05 (local, unpublished)

- Carry held CHERRY modifier outputs into native mouse events, restoring shortcuts such as TradingView's Shift-click ruler while remapping is enabled. Support clicks, movement, drags and scrolling, including remapped Command/Option/Control.
- Preserve native event flags from other keyboards without reusing stale keyboard-time snapshots. Clear held state on release, disconnect and Pause; remove the mouse event tap when capture stops.
- Add 12 regression checks covering Shift, overlapping devices, remapped and disabled modifiers, native flags and cleanup. Physically confirmed by the user in TradingView on the F1 receiver on 2026-11-05 after installation; the ruler works with remapping enabled.
- Retain the installed privileged broker and capture helper. Published v0.4.5 downloads remain build 16.

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
