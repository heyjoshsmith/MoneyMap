#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/moneymap-plaid-fixtures.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_root/MoneyMapShared/PlaidEnrichment.swift" \
  "$repo_root/MoneyMapMac/PlaidCredentialStore.swift" \
  "$repo_root/MoneyMapMac/MacPlaidAPIClient.swift" \
  "$repo_root/Scripts/Fixtures/PlaidAPIFixtures.swift" \
  -o "$fixture_dir/plaid-fixtures"
"$fixture_dir/plaid-fixtures"
