#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/moneymap-background-fixtures.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
xcrun swiftc -swift-version 5 -parse-as-library \
 "$repo_root/MoneyMapMac/MacBackgroundLifecycle.swift" \
 "$repo_root/Scripts/Fixtures/MacBackgroundLifecycleFixtures.swift" \
 -o "$fixture_dir/background-fixtures"
"$fixture_dir/background-fixtures"
