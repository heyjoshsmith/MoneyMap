#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/moneymap-account-fixtures.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
xcrun swiftc -swift-version 5 -parse-as-library \
 "$repo_root/MoneyMapShared/PlaidEnrichment.swift" \
 "$repo_root/MoneyMapShared/BankEnrichmentViews.swift" \
 "$repo_root/MoneyMapMac/MacAccountCapabilities.swift" \
 "$repo_root/Scripts/Fixtures/MacAccountCapabilityFixtures.swift" \
 -o "$fixture_dir/account-fixtures"
"$fixture_dir/account-fixtures"
