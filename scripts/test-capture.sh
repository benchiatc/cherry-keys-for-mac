#!/bin/bash
set -euo pipefail
# Deliberately refuses root: these tests must never open a hardware device.
if [ "$(id -u)" -eq 0 ]; then
  echo "Run capture argument tests as a normal user, never as root." >&2
  exit 77
fi
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/cherry-capture-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -target arm64-apple-macos13.0 Sources/Shared/CherryDeviceIdentity.swift Sources/HIDCapture/*.swift -o "$test_dir/CherryKeysHIDCapture-arm64" -framework IOKit -framework SystemConfiguration -framework Foundation
swiftc -target x86_64-apple-macos13.0 Sources/Shared/CherryDeviceIdentity.swift Sources/HIDCapture/*.swift -o "$test_dir/CherryKeysHIDCapture-x86_64" -framework IOKit -framework SystemConfiguration -framework Foundation
swiftc Sources/HIDCapture/HIDValueDecoder.swift Tests/HIDValueDecoderTests.swift -o "$test_dir/HIDValueDecoderTests" -framework IOKit -framework Foundation
"$test_dir/HIDValueDecoderTests"
swiftc Sources/Shared/CherryDeviceIdentity.swift Tests/CherryDeviceIdentityTests.swift -o "$test_dir/CherryDeviceIdentityTests"
"$test_dir/CherryDeviceIdentityTests"
python3 - "$test_dir/CherryKeysHIDCapture-arm64" <<'PY'
import os, subprocess, sys
binary = sys.argv[1]
cases = [
    ([], 64),
    (["0", "2", "/tmp"], 64),
    (["-1", "2", "/tmp"], 64),
    (["4294967295", "2", "/tmp"], 64),
    (["4294967296", "2", "/tmp"], 64),
    ([str(os.getuid()), "1", "/tmp"], 64),
    ([str(os.getuid()), "-3", "/tmp"], 64),
    ([str(os.getuid()), "2147483648", "/tmp"], 64),
    ([str(os.getuid()), "2", "relative/path"], 64),
    ([str(os.getuid()), str(os.getpid()), "/tmp/does-not-exist"], 77),
    ([str(os.getuid()), str(os.getpid()), "/etc/passwd"], 77),
]
for arguments, code in cases:
    result = subprocess.run([binary, *arguments], capture_output=True, text=True, timeout=3)
    assert result.returncode == code, (arguments, result.returncode, result.stderr)
    assert not result.stdout, "The helper must not emit captured input to stdout."
    if code == 77:
        assert "No devices opened" in result.stderr
print(f"PASS: {len(cases)} capture argument/nonroot privilege checks; arm64 and x86_64 compiled. No devices opened.")
PY
