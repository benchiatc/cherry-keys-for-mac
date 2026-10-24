#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
swiftc -swift-version 5 -framework AppKit -framework ApplicationServices -framework IOKit -framework Carbon -framework ServiceManagement -framework Security Sources/Shared/*.swift Sources/CherryKeysMac/CaptureRecovery.swift Sources/CherryKeysMac/Model.swift Sources/CherryKeysMac/HIDRouter.swift Sources/CherryKeysMac/InputEngine.swift Tests/InputEngineTests.swift -o .build/InputEngineTests
.build/InputEngineTests

swiftc Sources/CherryKeysMac/CaptureRecovery.swift Tests/CaptureRecoveryTests.swift -o .build/CaptureRecoveryTests
.build/CaptureRecoveryTests
