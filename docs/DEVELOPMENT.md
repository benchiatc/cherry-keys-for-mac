# Development and distribution

## Reproducible local workflow

Install Apple's Command Line Tools, then use the commands in the README. There is no third-party package lockfile because the app has no third-party runtime dependencies. SDK/toolchain versions still affect output; release notes should state the toolchain, OS and architectures tested.

`build.sh` stages a universal bundle without installing it or registering services. `test-service.sh` requires the signing identity and a prior build. Tests run as a normal user and never seize devices, register a service or install software. The CI workflow creates an ephemeral local signing identity on its macOS runner; no signing secrets are uploaded.

`test-input.sh` runs key-routing, transport-routing and recovery checks. Keep the transport matrix intact when adding hardware or changing trigger lookup: the same profile must apply across connections, preset/Fn layers must stay separate, and disconnect cleanup must not invoke a pending action or release another connection's key. The transport fixtures contain only generic model metadata and synthetic registry IDs.

Format Swift with `xcrun swift-format format --in-place --recursive Sources Tests`. Review changes semantically; formatting is not a security check.

## Signing

`scripts/sign-local.py` temporarily includes the isolated keychain in the user search list while signing, then restores the original list. This supports older macOS signing tools without changing certificate trust or the default keychain. Signing operations are serialized to avoid overlapping search-list changes.

The isolated local identity is for source builders. All three executables must have the same certificate, with their respective identifiers. XPC and child validation pin that certificate. Do not distribute a private key or share a local signing identity with users.

For public binary releases, implement and test an explicit Developer ID signing/notarization workflow and macOS compatibility matrix. The current scripts produce locally signed development builds, not notarized production releases. Never instruct users to disable Gatekeeper, SIP, signature validation or privacy controls. Replacing the signer can require macOS permission/helper reapproval.

The privileged executable snapshot hardening has automated nonroot coverage; its root launch, protected-directory permissions and Pause/Enable cleanup were verified on one installed Mac. Wired typing, modifier mappings, Caps/Num behavior and immediate LED feedback were also physically confirmed. The receiver through a USB hub and both Bluetooth slots were subsequently rechecked successfully on the hardened build. Clean-machine setup, reboot/crash checks and the broader compatibility matrix remain required before public binary release.

## Upgrades and removal

For an upgrade that changes the broker, use **Remove helper** in the installed old app, quit it, replace the app at its canonical Applications path, reopen, and complete helper setup again. If macOS reports a launch-constraint failure after replacing the bundle, refresh its LaunchServices registration with the system `lsregister -f` tool and remove/register the helper again; never disable launch constraints or signature validation. User settings should be preserved. Keep a known-good signed bundle for rollback. Do not overwrite a live privileged process's files as an update mechanism.

To uninstall: Pause, choose **Remove helper**, disable Launch at login, quit, and move the app to Trash. Optionally remove its Accessibility/Input Monitoring entries in System Settings and its settings directory in Application Support. Keep backups if profiles are needed. Delete the isolated Signing directory only if you no longer need that local signing identity. No global uninstall script or unrelated remapper cleanup is shipped.

## Source publication

Run `python3 scripts/check-public-source.py` and `python3 scripts/export-source.py`. The ZIP uses a strict allowlist of source, tests, build scripts, documentation and assets. It does not include Git history, local settings, signing material, binaries or reverse-engineering artifacts. Extract it into a new standalone directory before initializing a public Git repository. Check the exact staged files with a secret scanner before pushing.

Run Gitleaks separately against the exported directory and, once a standalone repository exists, its full history. The built-in privacy check is supplementary and deliberately conservative; it is not a credential scanner or guarantee against disclosure. Review assets and documents manually too.

## DMG packaging

Run `./scripts/package.sh` after building. The output is a compressed read-only DMG in `dist/app/`, with an Applications shortcut, a short installation guide and the MIT license. Existing user settings and local signing keys are never packaged. Temporary payload copies stay under `.build/dmg.noindex` and are removed after packaging. The script verifies the copied app signature and image integrity before replacing the distribution artifact, and writes a basename-only SHA-256 manifest. The source ZIP remains a separate contributor download in `dist/source/`. Each folder has its own `SHA256SUMS` manifest.

Test each image by mounting it read-only without opening Finder, verifying the mounted app's signature and version, checking the Applications shortcut and bundled files, and ejecting it. Never launch/register the app from the mounted image: install it at the canonical Applications path. DMG packaging does not provide Developer ID signing or notarization; apply the release signing/notarization requirements above before a public binary release.
