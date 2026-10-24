#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
[[ $(id -u) != 0 ]] || { print -u2 'Run these tests as a normal user.'; exit 77; }
swiftc -swift-version 5 Sources/CherryKeysMac/HelperSetupResult.swift Tests/HelperSetupTests.swift -o .build/HelperSetupTests -framework ServiceManagement -framework Foundation
.build/HelperSetupTests
swiftc -swift-version 5 Sources/Shared/*.swift Tests/CaptureServiceTests.swift -o .build/CaptureServiceTests -framework Security -framework Foundation
python3 scripts/sign-local.py local.cherrykeys.mac.tests .build/CaptureServiceTests
.build/CaptureServiceTests "$PWD"
swiftc -swift-version 5 Sources/Shared/*.swift Tests/CaptureXPCTests.swift -o .build/CaptureXPCTests -framework Security -framework Foundation
python3 scripts/sign-local.py local.cherrykeys.mac.tests.xpc .build/CaptureXPCTests
.build/CaptureXPCTests
python3 - "$PWD/.build/package.noindex/Cherry Keys for Mac.app/Contents/MacOS/CherryKeysCaptureService" <<'PY'
import subprocess,sys
for args, expected in [([],77),(['not-a-service-argument'],64)]:
    result=subprocess.run([sys.argv[1],*args],capture_output=True,text=True,timeout=3)
    assert result.returncode == expected,(result.returncode,result.stderr)
    assert not result.stdout
print('PASS: managed broker rejects nonroot and unexpected arguments; no service registered or hardware opened.')
PY

swiftc -swift-version 5 Sources/Shared/*.swift Sources/CaptureService/CaptureExecutable.swift Tests/CaptureExecutableTests.swift -o .build/CaptureExecutableTests -framework Security -framework Foundation
python3 scripts/sign-local.py local.cherrykeys.mac.tests.snapshot .build/CaptureExecutableTests
.build/CaptureExecutableTests "$PWD/.build/package.noindex/Cherry Keys for Mac.app/Contents/MacOS/CherryKeysHIDCapture"
