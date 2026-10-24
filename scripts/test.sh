#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
TEST_BINARY="$(mktemp "$PWD/.build/ModelTests.XXXXXX")"
trap 'rm -f "$TEST_BINARY"' EXIT
swiftc -swift-version 5 Sources/CherryKeysMac/Model.swift Tests/ModelTests.swift -o "$TEST_BINARY"
"$TEST_BINARY"
