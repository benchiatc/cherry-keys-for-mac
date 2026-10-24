# Adding CHERRY hardware

## Current identity policy

USB matching uses CHERRY vendor `046A`, followed by keyboard/consumer collection checks. Bluetooth currently requires vendor `0687`, product `C113`, VendorIDSource `1`, product name `CHERRY KW X ULP`, and transport `Bluetooth Low Energy`. USB and Bluetooth vendor namespaces are different. These fields are self-reported and can be copied; they are compatibility selectors, not security credentials.

Do not treat a model ID, firmware revision, USB port, registry ID or driver-extension identifier as a physical keyboard serial. KW X ULP wired USB exposes no serial descriptor. Its two BLE slots have different connection identities. Private addresses, UUIDs and raw registry dumps should not be committed.

## Development procedure

1. Keep a mouse or separate keyboard available. Pause remapping before changing capture code.
2. Inspect the new model locally using `ioreg -r -c IOHIDDevice -l` or a read-only IOHID query. Record only generic manufacturer/model, vendor/product/source/transport and HID report layout in contributions. Keep raw output private.
3. Inspect all input collections and standard LED elements. A keyboard with combined pointer input must not be seized unless all required input is handled. Do not remove fail-open collection validation to make discovery appear successful.
4. Update `CherryDeviceIdentity` with the narrowest observed policy. Update both helper discovery and relay checks through this shared policy. Add positive and negative identity tests, especially other manufacturers' receivers.
5. If an auxiliary vendor report is present, establish its report ID/page and behavior before deciding to ignore it. Scope exceptions to the verified model. Do not experiment with vendor output/feature reports or firmware writes as part of routine remapping support.
6. Add decoder/routing regressions using metadata and injected event sinks; do not commit real key logs or require hardware for unit tests.
7. Build/sign all components with the same certificate and run every test script. Install only after quitting the existing app. If broker code changed, remove the registered helper using the old app first and register the new build after installation.
8. Perform the manual checks below for every connection mode. Report OS version/architecture and model/firmware revision without hostnames, account names, addresses, serials or UUIDs.

## Manual acceptance checklist

- Ordinary typing, held keys, repeat, modifiers and existing assignments.
- A second, non-CHERRY keyboard remains unaffected while both are connected.
- Caps input state and physical LED; Num numeric/navigation state and LED.
- Media keys, hardware Fn behavior, international/layout-specific keys.
- Pause/Enable, Quit, disconnect/reconnect and transport switching with held keys.
- Sleep/wake, session lock and Secure Keyboard Entry restore native input safely.
- Approval/setup, helper removal and reboot behavior on a clean macOS user account.

KW X ULP acceptance covered typing, modifier remapping, Caps/Num behavior/LEDs in all four modes and recapture across Bluetooth/wired changes. It did not exhaust the full checklist. Physical feedback cannot be inferred from unit tests or successful HID writes alone.

## Consumer launch controls

The observed KW X ULP alternate F8, F11 and F12 usages are Consumer page `12`: `0x223` (AC Home), `0x192` (AL Calculator) and `0x18A` (AL Email Reader). `ConsumerControl` keeps their raw usages in a separate persisted trigger namespace, rather than mislabelling them as NX media codes or standard F-keys. The GUI provides an explicit picker because macOS may not expose these controls to its local event monitor. Preset consumer triggers and standard F-key triggers are independent, with no fallback between them. The UI labels both layers using the KW X ULP Fn-light-off arrangement: F12 is the Mail preset and Fn + F12 is standard F12. Ctrl+Fn reverses the keyboard's layer selection; the app routes actual HID events and does not observe hardware Fn-lock state. Existing saved triggers are not automatically migrated. Defaults execute in the unprivileged GUI on release; Pause/disconnect cancel pending actions. Unknown usages retain the native-input recovery path. The three defaults were physically confirmed over the F1 receiver on v0.4.5 build 14. Build 16 replaces the temporary inheritance behavior with independent layer routing and clearer labels. Automated regressions cover separate mappings, defaults, disable, held-action stability and Bluetooth routing. On the F1 receiver, the user confirmed that the customized F12 preset launches its application while Fn + F12 does not, and Calculator works. Browser Home had no visible effect in that session; its foreground-browser behavior remains unverified. Independent-layer physical checks on the other transports remain outstanding.

## Mapping consistency across connections

The active profile supplies the same assignments to the router for F1 receiver, F2/F3 Bluetooth and wired USB. Assignment lookup uses only the normalized trigger kind and code. Vendor/product/transport fields determine which hardware may enter capture; registry IDs track held input and disconnect cleanup, not profile selection. Preset and standard F-key layers remain independent on every connection.

`TransportRoutingTests` exercises identity acceptance, HID-value decoding and routing using synthetic registry IDs and normalized elements for all four modes. It models separate USB keyboard/consumer interfaces and combined Bluetooth interfaces. Its 78 checks cover shared mappings, independent layers, preset defaults, ordinary/media passthrough, profile changes, other-brand exclusion and all 12 directed channel handoffs, including cancelled held actions and late releases from the old channel. It runs under `scripts/test-input.sh` and CI, without hardware access or real event posting. These fixtures are not captured HID reports; radio timing, device report generation and physical mode switching still require hardware acceptance.
