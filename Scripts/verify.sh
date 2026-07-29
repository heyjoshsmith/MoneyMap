#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-AddMoneyMap.xcodeproj}"
SCHEME="${SCHEME:-MoneyMap}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/MoneyMapVerifyDerivedData.noindex}"
REQUIRED_WATCH_SDK="${REQUIRED_WATCH_SDK:-watchos26.2}"

echo "Using Xcode:"
xcodebuild -version

if ! xcodebuild -showsdks | grep -q "$REQUIRED_WATCH_SDK"; then
  echo "Missing $REQUIRED_WATCH_SDK; downloading watchOS platform support."
  xcodebuild -downloadPlatform watchOS
fi

echo "Checking staged/unstaged diff whitespace."
git diff --check

echo "Building $SCHEME scheme for generic iOS."
xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Building MoneyMap Release target for iPhoneOS."
xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -target MoneyMap \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Building MoneyMapTests Debug target for iPhone Simulator."
xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -target MoneyMapTests \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Verification complete."
