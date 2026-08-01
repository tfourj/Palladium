#!/bin/bash

set -euo pipefail

SERVICE_TEST_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_TEST_REPO_ROOT="$(cd "$SERVICE_TEST_SCRIPT_DIR/.." && pwd)"
SERVICE_TEST_BUILD_DIR="$(mktemp -d)"
SERVICE_TEST_BINARY="$SERVICE_TEST_BUILD_DIR/swift-model-tests"

cleanup() {
    rm -rf "$SERVICE_TEST_BUILD_DIR"
}
trap cleanup EXIT

xcrun swiftc \
    "$SERVICE_TEST_REPO_ROOT/Palladium/Models/DownloadServiceDomain.swift" \
    "$SERVICE_TEST_REPO_ROOT/Palladium/Models/TemporaryDownloadRetentionPolicy.swift" \
    "$SERVICE_TEST_REPO_ROOT/scripts/swift_tests/SwiftModelTests.swift" \
    -o "$SERVICE_TEST_BINARY"

"$SERVICE_TEST_BINARY"
