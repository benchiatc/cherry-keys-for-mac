<p align="center">
  <img src="Resources/AppIcon.png" alt="Cherry Keys for Mac app icon" width="144" height="144">
</p>

# Cherry Keys for Mac

**Make your CHERRY keyboard feel at home on a Mac.**

I built this because the keyboard I wanted to use shipped with Windows-only [CHERRY KEYS software (official download)](https://www.cherry.de/en-gb/products/software-services/cherry-keys). I investigated its behavior, designed a native Mac alternative, and tested it against the real keyboard across every connection mode. The work went beyond mapping keys: isolating the right device, separating privileged capture from user actions, fixing Bluetooth LED feedback, and recovering after sleep and lock. Each fix followed a user-visible problem and a physical check. This project turns that work into an open-source foundation other Mac users can extend for their own CHERRY hardware.

**4 connection modes verified · 171 key/transport checks + 10 recovery checks · 0 third-party runtime dependencies**

Swift and SwiftUI. MIT licensed. Independent community software, not affiliated with or endorsed by CHERRY.

Current preview: **v0.4.5 (build 16)** · [Changelog](CHANGELOG.md) · [GitHub release](https://github.com/benchiatc/cherry-keys-for-mac/releases/tag/v0.4.5)

### What you can do

- **Make the layout feel native:** remap keys and swap Windows/Alt to Command/Option.
- **Customize both layers:** assign preset commands and standard Fn + F-keys independently.
- **Launch Mac actions:** Spotlight, screenshots, Emoji & Symbols and media controls.
- **Automate everyday tasks:** create shortcuts, text snippets and recorded keyboard macros.
- **Keep your setup across connections:** use the same selected profile over the receiver, Bluetooth or USB cable.
- **See your lock state:** synchronize Caps Lock and Num Lock behavior with their LEDs.
- **Keep it running quietly:** use the menu bar and resume automatically after sleep or unlock.

## Contents

- [Changelog](CHANGELOG.md)
- [Install and get started](#install-and-get-started)
- [Everyday use](#everyday-use)
- [Compatibility](#compatibility)
- [How it works](#how-it-works)
- [Hardware specifications](#hardware-specifications)
- [Mapping behavior and limits](#mapping-behavior-and-limits)
- [Build, test and distribute](#build-test-and-distribute)
- [Security](#security)
- [Contributing](#contributing)
- [License and provenance](#license-and-provenance)

## Install and get started

You need a **Mac running macOS 13 or later** and a CHERRY keyboard. The **KW X ULP** is the model tested so far. Your other keyboards can stay connected.

| Choose | Best for | What you need |
| --- | --- | --- |
| [Option A: Install the DMG](#option-a-install-the-dmg) | Using the app with the least setup | The packaged app; no Terminal or compiler |
| [Option B: Build from source](#option-b-build-from-source) | Reviewing the implementation, customizing behavior, adding keyboard support or contributing | The source code and Apple's Command Line Tools |

Both options install the same app and use the same macOS permission setup.

### Option A: Install the DMG

**Choose this if you just want to use the app.** You do not need to download the source code or build anything.

1. Download **[CherryKeysMac-0.4.5-macOS-universal.dmg](https://github.com/benchiatc/cherry-keys-for-mac/releases/download/v0.4.5/CherryKeysMac-0.4.5-macOS-universal.dmg)**. The packaged app is in `dist/app/`.
2. Double-click the DMG to open it.
3. Drag **Cherry Keys for Mac.app** onto the **Applications** shortcut in the window.
4. Eject the disk image, then open **Cherry Keys for Mac** from Applications.
5. Continue with [Finish setup](#finish-setup-both-options) below.

Keep the app's name unchanged. If an older copy is installed, quit it before replacing it; see [upgrade instructions](docs/DEVELOPMENT.md#upgrades-and-removal) if its helper changed.

**Already using another keyboard app?** If your CHERRY keyboard is mapped in Karabiner-Elements, BetterTouchTool or a similar app, disable those mappings for the CHERRY keyboard before enabling Cherry Keys. Running both can cause conflicting shortcuts or prevent Cherry Keys from accessing the keyboard.

The current DMG is a locally signed development build. A public Apple-notarized release has not been published yet; see [signing and updates](#signing-and-updates) for release details.

### Option B: Build from source

**Choose this if you want to explore the code, make changes, support another keyboard or contribute.** This route creates the app directly from the source on your Mac, ready for your own development workflow.

1. Get the source with **[Download ZIP](https://github.com/benchiatc/cherry-keys-for-mac/archive/refs/heads/main.zip)**, then double-click the ZIP to extract it. Contributors can clone the GitHub repository instead.
2. Open **Terminal** from Applications → Utilities.
3. Paste this command and press Return. If macOS offers to install Command Line Tools, finish that installation before continuing. If they are already installed, continue to the next step.

   ```sh
   xcode-select --install
   ```

4. In Terminal, type `cd` followed by a space. Drag the extracted project folder from Finder into Terminal, then press Return. This selects the project folder.
5. Paste these commands and press Return:

   ```sh
   python3 scripts/prepare-local-signing.py
   ./scripts/build.sh
   open .build/package.noindex
   ```

6. When Finder opens, drag **Cherry Keys for Mac.app** into **Applications**. Keep its name unchanged, then open it from Applications.
7. Continue with [Finish setup](#finish-setup-both-options) below. For tests and development tools, see [Build, test and distribute](#build-test-and-distribute).

The build can take a few minutes. If a command reports an error, stop there and include that error in a support request—do not run the commands with `sudo`. Before replacing an existing installation, quit it and follow the [upgrade instructions](docs/DEVELOPMENT.md#upgrades-and-removal).

### Finish setup (both options)

**1. Allow keyboard access.** In **System Settings → Privacy & Security**, enable **Cherry Keys for Mac** in both:

- **Accessibility** — lets the app send your remapped keys.
- **Input Monitoring** — lets it read the CHERRY keyboard.

The app has buttons to open these settings. Quit and reopen it after enabling both permissions.

**2. Approve the helper.** Click **Set up helper** in the app. If macOS requests approval, complete it in **System Settings → General → Login Items & Extensions**. The app should then show **Helper approved**.

This is a one-time setup. You should not need an administrator password every time you pause or enable remapping.

**3. Make it yours.** For a familiar Mac modifier layout, click **Swap Windows ↔ Alt**: physical Alt becomes Command, and the Windows key becomes Option. For another action, choose **Add assignment**, select a trigger (or use **Detect key**), choose an action, and save.

**Preset or Fn key?** On the KW X ULP with its Fn light off, choose **F12 — Mail (preset)** to change the Mail button, or **Fn + F12 — standard F12** to assign the other layer. They are separate; Ctrl+Fn reverses which layer needs Fn. Browser Home and Calculator have named preset triggers too.

**4. Enable remapping.** Click **Enable remapping**, then try your keys in TextEdit. Your selected profile follows the keyboard when you switch between its supported connection modes.

## Everyday use

| What you want | What to do |
| --- | --- |
| Keep remapping in the background | Close the window with Command+W; the menu-bar icon stays active |
| Change your assignments | Open Cherry Keys from its menu-bar icon |
| Temporarily use the normal keyboard behavior | Choose **Pause remapping** |
| Stop the app | Choose **Quit** |
| Start the app when you log in | Enable **Launch at login** |
| Keep different sets of assignments | Create profiles and select the one you want |
| Change preset F12 without changing Fn + F12 | Assign **F12 — Mail (preset)**; leave the standard trigger unchanged |
| Recover if a mapping gets in your way | Use the menu-bar Pause button, or press **Control–Option–Command–Escape** on CHERRY |

Each app launch starts with remapping paused. Once enabled, it resumes automatically after sleep/wake or lock/unlock; you do not need to enable it again. A manual Pause stays paused. Remapping is suspended during protected password entry, so lock-screen input uses native keyboard behavior.

Profiles can be exported and imported as JSON. They may contain private text or file paths, so review them before sharing. Settings and a rolling backup stay on your Mac.

## Compatibility

**Tested model: CHERRY KW X ULP.**

| Connection | Guided checks passed |
| --- | --- |
| F1 wireless receiver, including through a USB hub | Typing, modifier mappings, Caps/Num behavior and LEDs |
| F2 Bluetooth 1 | Same, with immediate LED feedback |
| F3 Bluetooth 2 | Same, including capture after changing Bluetooth slots |
| USB cable | Same, with immediate LED feedback |

All four modes were rechecked on **v0.4.3 build 12** after helper hardening. Automatic recovery after sleep and lock was physically confirmed on **v0.4.4 build 13**. The latest preset/Fn separation and Calculator were physically confirmed on **v0.4.5 build 16 over F1**; the other three connections have automated coverage for this change but await that specific physical recheck. These results come from one keyboard on one Apple silicon Mac; they are not a guarantee for every model, layout or macOS version.

Other CHERRY USB keyboards may work but are untested. Other CHERRY Bluetooth models need their device identities verified and added. Non-CHERRY keyboards stay on their normal macOS path; the connected Logitech receiver was verified as excluded by the device filter.

No Karabiner, Wine, Windows VM or driver extension is required. If another remapper already controls the CHERRY keyboard, release that device in the other app before enabling this one.

The sections below cover the implementation, extension points and validation for contributors.

## How it works

The app takes exclusive control of supported CHERRY keyboard interfaces, routes their input through the selected profile, and sends replacement key events to macOS. Input retains its device identity before macOS merges keyboards, so other brands' keyboards are left alone.

The design separates three responsibilities:

| Process | Runs as | Responsibility |
| --- | --- | --- |
| App | Logged-in user | Interface, profiles, mapping and action execution |
| Approved broker | Root | Authenticate the app and launch the fixed capture executable |
| Bounded capture child | Root | Read verified CHERRY interfaces and update standard lock LEDs |

The privileged processes do not execute profiles or arbitrary commands. The broker validates a protected snapshot of the capture executable before launching it, avoiding replacement of a user-writable binary between verification and execution. IPC uses certificate-authenticated XPC and a private Unix-domain socket.

Pause, Quit, disconnect and failure release synthesized keys. Capture heartbeats expire after two seconds, and a capture session has a four-hour ceiling. Temporary sleep/session/secure-input interruptions preserve enabled intent; permanent errors and explicit Stop cancel recovery. Workspace notifications and a 500 ms recovery check restart capture when the console session is active and Secure Keyboard Entry has ended. Cancelled macros are not replayed on wake.

See [architecture and privilege boundaries](docs/ARCHITECTURE.md) for the full process and lifecycle design.

## Hardware specifications

| KW X ULP mode | Reported identity | Input layout |
| --- | --- | --- |
| F1 receiver | USB `046A:C111`, CHERRY Wireless Device | Separate keyboard and consumer-control interfaces |
| F2 / F3 Bluetooth | BLE `0687:C113`, CHERRY KW X ULP | Combined keyboard, consumer and auxiliary vendor collections |
| USB cable | USB `046A:C112`, CHERRY Corded Keyboard | Separate keyboard and consumer-control interfaces |

USB matching uses CHERRY vendor `046A`, then validates keyboard and associated consumer collections. BLE matching requires vendor `0687`, product `C113`, Bluetooth vendor source `1`, the exact model name, and Bluetooth Low Energy transport. The two Bluetooth slots expose distinct connection identities but the same model/report layout. Vendor IDs are self-reported compatibility selectors, not cryptographic authentication.

The verified BLE model's opaque vendor input report `0x11` is ignored. Unexpected unsupported input collections cause capture to stop rather than swallowing unhandled input. CHERRY mice and separate vendor-control interfaces are excluded. Caps/Num indicator writes target only standard HID LED page `8`, usages `1` and `2`; no firmware or vendor-lighting commands are sent.

There is no reliable shared physical-unit identifier established across all four modes. The active profile applies to every captured CHERRY keyboard, not a uniquely enrolled physical unit. Profile selection is manual.

To extend support, follow [adding hardware](docs/HARDWARE.md). Keep raw device dumps, serials, addresses and connection UUIDs private.

## Mapping behavior and limits

### Actions

Supported actions include modifier remapping, shortcuts, Unicode text insertion, recorded keyboard macros, application/file/folder/website launch, media/volume/brightness controls, browser back/forward, default mail app launch, disable, screen lock and sleep. There are **18 Mac action presets**, including Spotlight, Emoji & Symbols, screenshots, window/tab controls, Find and Select All.

**Swap Windows ↔ Alt** creates four editable assignments, covering both sides of the keyboard. It replaces existing assignments on those four modifier keys. Modifier mappings preserve held-key behavior. Ordinary assignments apply without Command/Control/Option/Shift held.

Text, macro, launch and system actions run on trigger release. Keyboard shortcuts preserve down/up and repeat. Key labels follow physical US positions; the active layout and application shortcut settings affect interpretation. Hardware Fn may not generate an OS-visible event. Caps Lock and hardware Fn are not assignable triggers.

### Alternate F8 / F11 / F12 functions

The KW X ULP can send Consumer-page controls instead of regular function keys. The app and DMG recognize these from v0.4.5 onward without pausing capture:

| Trigger in the editor | HID page / usage | Default behavior |
| --- | --- | --- |
| F8 — Browser Home (preset) | `12 / 0x223` | Send Command–Shift–H to the foreground app; supported browsers use it for their homepage |
| F11 — Calculator (preset) | `12 / 0x192` | Open macOS Calculator |
| F12 — Mail (preset) | `12 / 0x18A` | Open your default mail app without composing a message |

**Preset functions and standard F-keys are independently assignable.** With the KW X ULP Fn light off, F8/F11/F12 send the presets above; holding Fn sends standard F8/F11/F12. Ctrl+Fn changes Fn Lock and reverses the layers. The app labels the two choices, for example **F12 — Mail (preset)** and **Fn + F12 — standard F12**, and explains this in the main window and assignment editor. Labels describe the Fn-light-off arrangement; the app routes the event actually sent by the keyboard and does not read the Fn light.

The selected profile is shared across the F1 receiver, F2/F3 Bluetooth and wired USB. Connection identity is used to track held keys and disconnects; it does not select a different mapping or merge the two layers. Automated tests cover all four normalized input paths and all 12 directed channel transitions. These tests do not replace physical checks on each connection.

Choose the preset trigger to replace its built-in action, or the standard F-key trigger to assign the Fn layer. There is no inheritance between them. For example, assign **F12 — Mail (preset)** to a mail application while leaving **Fn + F12 — standard F12** unassigned or mapping it to something else. Other models' Fn layouts may differ. Existing saved triggers retain their meaning; builds do not automatically move users' assignments between layers.

Defaults and custom launch actions run once on release. Unknown controls still release capture and restore native input instead of silently swallowing a key. Use v0.4.5 or later for these controls. On build 16 over the F1 receiver, the user confirmed the independent layers: the customized F12 preset opens the selected application, Fn + F12 does not invoke that assignment, and Calculator works. Browser Home produced no visible effect in that session, so browser-specific Home behavior remains unverified.

Usage names follow the [USB-IF HID Usage Tables](https://www.usb.org/sites/default/files/hut1_21_0.pdf). Browser Home uses the [standard Safari homepage shortcut](https://support.apple.com/en-gb/guide/safari/cpsh003/mac); the foreground application's shortcuts and settings determine its effect.

### Lock keys

Unassigned Num Lock toggles numeric/navigation keypad mode and starts enabled per app session. Navigation maps 1/2/3/4/6/7/8/9 to End/Down/Page Down/Left/Right/Home/Up/Page Up; 0 emits Help/Insert and decimal emits Forward Delete. Keypad 5 is silent. Explicit assignments take precedence.

Caps/Num LEDs follow the relayed state where standard outputs are available. LED values are sent on state changes and committed together to avoid polling delay and redundant Bluetooth transactions. Indicator color is a hardware property.

### Profiles and limits

Settings live under `~/Library/Application Support/CherryKeysMac/`, with atomic saves and one rolling backup. JSON reads/saves are limited to 4 MiB; configurations allow up to 100 profiles, 1,000 assignments per profile and 64 KiB of text per assignment. Macros allow up to 4,000 events, 30 seconds per delay and five minutes total duration.

Macro recording is limited to keyboard input inside the editor. Remapping is released while assignments are edited. Profiles can contain sensitive text and local paths; imported launch/file/website assignments can invoke other applications with your user permissions.

### Known limits

This is a user-session app, not a login-screen or FileVault keyboard driver. It does not implement firmware updates, battery telemetry, programmable backlighting, mouse assignments or automatic per-device profile selection. Applications may reject synthesized input.

Core transport behavior and sleep/lock recovery have physical acceptance, but complete media-key coverage, international layouts, adverse reconnects, crash handling, reboot and clean-machine setup need broader testing. Intel binaries compile; equivalent physical testing on Intel has not been established.

## Build, test and distribute

### Requirements

- macOS 13 or later and Apple Command Line Tools with a current SDK.
- Python 3 and the macOS `openssl`, `security`, `codesign` and `lipo` tools.
- No third-party runtime packages or libraries.

### Build and automated checks

```sh
python3 scripts/check-release.py
python3 scripts/prepare-local-signing.py
./scripts/build.sh
./scripts/test.sh
./scripts/test-input.sh
./scripts/test-capture.sh
./scripts/test-service.sh
xcrun swift-format lint --strict --recursive Sources Tests
```

The build produces a universal arm64/x86_64 app in `.build/package.noindex/Cherry Keys for Mac.app`. Install at exactly `/Applications/Cherry Keys for Mac.app`; that path is part of helper authentication. Never run the GUI or test suite as root.

Coverage includes model validation and private persistence, 93 key-routing checks, 78 transport-routing checks, 10 recovery checks, HID array decoding, manufacturer/transport rejection, nonroot helper rejection, helper setup, authenticated XPC and executable snapshot replacement/symlink checks. Event sinks are injected: automated tests do not seize hardware, post real keys or register privileged services. Hardware acceptance is separate. The macOS CI workflow builds and runs these checks with an ephemeral local signing identity.

### Signing and updates

Source builders create an isolated local signing identity under `~/Library/Application Support/CherryKeysMac/Signing`. Keep it private and retain it for future builds. All three executables must use the same certificate; changing signers can require macOS permission/helper reapproval. The script does not alter certificate trust or the default keychain.

Published DMGs are explicitly labelled locally signed development previews, not Developer ID notarized releases. Production distribution still needs a protected signing pipeline, notarization and clean-machine validation. Do not disable Gatekeeper, SIP or signature validation to install this app. For broker upgrades, removal and rollback, see [development and distribution](docs/DEVELOPMENT.md).

### Packages and source export

```sh
./scripts/package.sh
python3 scripts/check-public-source.py
python3 scripts/export-source.py
python3 scripts/check-release.py --app ".build/package.noindex/Cherry Keys for Mac.app" --dist
```

App packaging creates `dist/app/CherryKeysMac-<version>-macOS-universal.dmg`: a compressed, read-only image containing the signed app, an Applications shortcut, versioned setup instructions, changelog and the MIT license. `dist/app/SHA256SUMS` records its checksum. The package script rejects mismatched release docs/staged metadata and verifies the bundle signature and disk-image integrity; it does not notarize the app or grant permissions. Source export creates `dist/source/CherryKeysMac-source.zip` with its own `dist/source/SHA256SUMS`, from an explicit allowlist excluding settings, signing material, build outputs, investigation artifacts and Git history. Run a credential scanner on the actual exported/staged files and any history you intend to publish. Do not upload a parent workspace or private troubleshooting archives.

## Security

This app handles keyboard input and uses an approved root helper. Local-only operation reduces exposure but does not eliminate local privilege escalation, malicious-profile, device-spoofing or input-capture risks. No claim of vulnerability-free operation is made.

There is no telemetry, automatic updater, HTTP client/server or TCP listener. IPC is local. Explicit website/file/application assignments may open other programs, which can access the network. Review imported profiles and never store passwords in macros.

The source review identified and fixed a privileged executable-replacement race and unbounded profile reads. The exported source passed Gitleaks 8.30.1 credential scanning and the repository's privacy check. These are scoped checks, not independent penetration testing or proof of zero vulnerabilities. The hardened helper and core behavior were subsequently checked on real hardware; broader release gates remain documented in [the security review](docs/SECURITY-REVIEW.md).

### Reporting vulnerabilities

Use the repository’s [private vulnerability reporting form](https://github.com/benchiatc/cherry-keys-for-mac/security/advisories/new). If it is unavailable, request a private reporting channel without posting exploit details publicly.

Include the source revision, macOS/toolchain version, required privileges and a minimal reproduction. Redact account names, paths, device addresses/serials, profiles and credentials. Do not upload captured keystrokes.

## Contributing

Hardware support, layout fixes and reproducible bug reports are welcome. Start with:

- [Changelog](CHANGELOG.md)
- [Contribution guidelines](CONTRIBUTING.md)
- [Adding hardware support and manual checks](docs/HARDWARE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Development, upgrades and uninstall](docs/DEVELOPMENT.md)
- [Security audit scope and results](docs/SECURITY-REVIEW.md)

Describe the user-visible problem, the implementation decision, the evidence and what remains untested. Keep privileged changes small and add regressions at trust boundaries. Never include private profiles, signing keys, device traces or vendor binaries in a contribution.

## License and provenance

[MIT License](LICENSE). CHERRY names and marks belong to their respective owners; the license does not grant trademark rights.

The implementation was informed by analysis of CHERRY KEYS 1.0.7 behavior. No vendor binaries, extracted resources, Windows installer or local device traces are included. The app icon is AI-generated artwork. This is an independent native implementation, not an official CHERRY release or a port of proprietary source code.
