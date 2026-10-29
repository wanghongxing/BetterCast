#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
cp contributions/tests/ReceiverConnectionSmoke.swift "$TEST_DIR/main.swift"
SOURCES=()
for source in LegacyMacReceiver/Sources/LegacyMacReceiver/*.swift; do
    [[ "$source" == */main.swift ]] || SOURCES+=("$source")
done
swiftc -O -target x86_64-apple-macosx10.15 "${SOURCES[@]}" "$TEST_DIR/main.swift" -o "$TEST_DIR/test"
"$TEST_DIR/test"
