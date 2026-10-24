# Development and distribution

## Reproducible local workflow

Install Apple's Command Line Tools, then use the commands in the README. There is no third-party package lockfile because the app has no third-party runtime dependencies. SDK/toolchain versions still affect output; release notes should state the toolchain, OS and architectures tested.

`build.sh` stages a universal bundle without installing it or registering services. `test-service.sh` requires the signing identity and a prior build. Tests run as a normal user and never seize devices, register a service or install software. The CI workflow creates an ephemeral local signing identity on its macOS runner; no signing secrets are uploaded.

`test-input.sh` runs key-routing, transport-routing and recovery checks. Keep the transport matrix intact when adding hardware or changing trigger lookup: the same profile must apply across connections, preset/Fn layers must stay separate, and disconnect cleanup must not invoke a pending action or release another connection's key. The transport fixtures contain only generic model metadata and synthetic registry IDs.

Format Swift with `xcrun swift-format format --in-place --recursive Sources Tests`. Review changes semantically; formatting is not a security check.

## Signing

`scripts/sign-local.py` temporarily includes the isolated keychain in the user search list while signing, then restores the original list. This supports older macOS signing tools without changing certificate trust or the default keychain. Signing operations are serialized to avoid overlapping search-list changes.

The isolated local identity is for source builders. All three executables must have the same certificate, with their respective identifiers. XPC and child validation pin that certificate. Do not distribute a private key or share a local signing identity with users.

The published DMGs are locally signed development previews. Before production distribution, implement and test an explicit Developer ID signing/notarization workflow and broader macOS compatibility matrix. The current scripts produce locally signed development builds, not notarized production releases. Never instruct users to disable Gatekeeper, SIP, signature validation or privacy controls. Replacing the signer can require macOS permission/helper reapproval.

The privileged executable snapshot hardening has automated nonroot coverage; its root launch, protected-directory permissions and Pause/Enable cleanup were verified on one installed Mac. Wired typing, modifier mappings, Caps/Num behavior and immediate LED feedback were also physically confirmed. The receiver through a USB hub and both Bluetooth slots were subsequently rechecked successfully on the hardened build. Clean-machine setup, reboot/crash checks and the broader compatibility matrix remain outstanding for production distribution.

## Upgrades and removal

For an upgrade that changes the broker, use **Remove helper** in the installed old app, quit it, replace the app at its canonical Applications path, reopen, and complete helper setup again. If macOS reports a launch-constraint failure after replacing the bundle, refresh its LaunchServices registration with the system `lsregister -f` tool and remove/register the helper again; never disable launch constraints or signature validation. User settings should be preserved. Keep a known-good signed bundle for rollback. Do not overwrite a live privileged process's files as an update mechanism.

To uninstall: Pause, choose **Remove helper**, disable Launch at login, quit, and move the app to Trash. Optionally remove its Accessibility/Input Monitoring entries in System Settings and its settings directory in Application Support. Keep backups if profiles are needed. Delete the isolated Signing directory only if you no longer need that local signing identity. No global uninstall script or unrelated remapper cleanup is shipped.

## Source publication

Run `python3 scripts/check-public-source.py` and `python3 scripts/export-source.py`. The ZIP uses a strict allowlist of source, tests, build scripts, documentation and assets. It does not include Git history, local settings, signing material, binaries or reverse-engineering artifacts. Use a standalone checkout for publication, and review the extracted archive separately. Check the exact staged files with a secret scanner before pushing.

Run Gitleaks separately against the exported directory and, once a standalone repository exists, its full history. The built-in privacy check is supplementary and deliberately conservative; it is not a credential scanner or guarantee against disclosure. Review assets and documents manually too.

## DMG packaging

Run `./scripts/package.sh` after building. The output is a compressed read-only DMG in `dist/app/`, with an Applications shortcut, a versioned installation guide, changelog and the MIT license. Existing user settings and local signing keys are never packaged. Temporary payload copies stay under `.build/dmg.noindex` and are removed after packaging. The script first checks release metadata against the README/changelog and staged app, then verifies the copied app signature and image integrity before replacing the distribution artifact, and writes a basename-only SHA-256 manifest. The source ZIP remains a separate contributor download in `dist/source/`. Each folder has its own `SHA256SUMS` manifest.

Test each image by mounting it read-only without opening Finder, verifying the mounted app's signature and version, checking the Applications shortcut and bundled files, and ejecting it. Never launch/register the app from the mounted image: install it at the canonical Applications path. DMG packaging does not provide Developer ID signing or notarization; apply the release signing/notarization requirements above before production distribution.

## Release workflow

`Resources/Info.plist` is the app version/build authority. Increment `CFBundleShortVersionString` for each published release and increase `CFBundleVersion` monotonically. Documentation-only updates keep the app version/build unchanged. If a published preview receives a documentation/packaging refresh, disclose it in release notes and refresh the source ZIP, DMG and checksums together. App behavior changes require a new version/build. Current preview details are in the [changelog](../CHANGELOG.md).

1. Update version/build, README current preview/release/DMG links and the newest changelog entry together. Preserve historical acceptance versions: passing core checks on an older build does not establish that every new feature was tested on every connection.
2. Run `python3 scripts/check-release.py`. Build and run all four test scripts, formatting lint and privacy checks. CI checks both source metadata and the staged app. For a GUI/metadata-only update on a local machine, `CHERRY_GUI_ONLY=1 ./scripts/build.sh` can retain already-validated helper binaries; clean CI always builds every component.
3. Run `./scripts/package.sh`, then `python3 scripts/export-source.py`, then `python3 scripts/check-release.py --app ".build/package.noindex/Cherry Keys for Mac.app" --dist`. The last command verifies both checksum manifests and every source ZIP entry against the current allowlist/content. Re-export after any included file changes.
4. Mount the DMG read-only without launching the app. Check version/build/minimum macOS, universal architectures, bundle signature, versioned setup guide, changelog, license and Applications shortcut; eject afterward. Compare helper bytes against the prior release when claiming no privileged changes. Review/scanner-check the exact exported source, assets and release notes for private information.
5. Commit and push the release source; wait for CI. Create a draft GitHub prerelease targeting that full commit SHA. Attach the DMG, source ZIP and a combined basename-only `SHA256SUMS`; check uploaded sizes/digests before publication. Include the version/build, toolchain, validation scope, upgrade impact and signing/notarization status in its notes.
6. Publish the preview and verify the public download links. Do not move published version tags. Disclose any preview documentation/packaging refresh and its source revision in release notes; never silently replace artifacts. Later documentation may advance on `main`. This project has no automatic updater.

The local layout is `dist/app/<versioned DMG>` and `dist/app/SHA256SUMS`, plus `dist/source/CherryKeysMac-source.zip` and `dist/source/SHA256SUMS`. Git ignores generated distribution files; GitHub release assets provide binary downloads. Keep old local artifacts in private development storage or a separate versioned archive, not mixed into the current checksum manifest.
