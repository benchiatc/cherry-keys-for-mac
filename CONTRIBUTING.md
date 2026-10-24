# Contributing

Use small, reviewable changes with a concrete problem statement and validation. Keep hardware selectors, decoded key state, action execution and privileged code separated. Root code must never accept arbitrary commands, paths, mappings or code from a client.

Before a pull request:

1. Build and run the four test scripts in the README as a normal user. `test-input.sh` includes the four-mode transport matrix; preserve separate preset/Fn behavior and shared profiles.
2. Add meaningful regressions for behavior or trust-boundary changes. Use fake metadata/event sinks; tests must not generate real input or require root.
3. Format Swift, run the public-source privacy check and run `python3 scripts/check-release.py`. For a version change, update `Resources/Info.plist`, the README current preview/download links and `CHANGELOG.md` together.
4. State what was automated, physically tested and left unverified. Hardware additions should follow [HARDWARE.md](docs/HARDWARE.md).
5. Remove local paths, profile exports, addresses, serials, UUIDs, screenshots with private content and raw device logs. Do not include vendor binaries or signing material.

Report security issues privately using GitHub's private vulnerability reporting when enabled; see [the README security section](README.md#security). Do not put exploitation details or sensitive logs in public issues.

Contributions are licensed under the repository's MIT license. CHERRY trademarks remain their owners' property.

Maintainers: follow the [release workflow](docs/DEVELOPMENT.md#release-workflow) for staged version checks, packaging, source export, checksums and GitHub release publication. Published version tags must not be moved.
