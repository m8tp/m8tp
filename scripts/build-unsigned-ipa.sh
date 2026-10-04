#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo "This build requires a macOS machine with Xcode (GitHub Actions or Codemagic)." >&2
  exit 1
fi
mkdir -p build
python3 scripts/validate_project.py
# Tests use the same Foundation model compiled into the iOS application.
xcrun swiftc M8TPGTAMap/Sources/Models.swift scripts/ModelChecks.swift -o build/model-checks
build/model-checks M8TPGTAMap/Resources/catalog.json M8TPGTAMap/Resources/demo.json
xcodebuild -version
xcodebuild -project M8TPGTAMap.xcodeproj -scheme M8TPGTAMap \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
APP="build/DerivedData/Build/Products/Release-iphoneos/M8TPGTAMap.app"
test -d "$APP"
test -f "$APP/M8TPGTAMap"
# Refuse to package a simulator executable as an iPhone IPA.
xcrun vtool -show-build "$APP/M8TPGTAMap" > build/macho-platform.txt
if ! grep -Eq 'platform IOS$' build/macho-platform.txt; then
    echo "Expected an iOS device binary." >&2
    cat build/macho-platform.txt >&2
    exit 1
fi
rm -rf build/package
mkdir -p build/package/Payload
cp -R "$APP" build/package/Payload/
rm -f build/M8TP-GTA-Map-unsigned.ipa
(cd build/package && /usr/bin/zip -qry ../M8TP-GTA-Map-unsigned.ipa Payload)
python3 scripts/verify_ipa.py build/M8TP-GTA-Map-unsigned.ipa
shasum -a 256 build/M8TP-GTA-Map-unsigned.ipa > build/SHA256SUMS.txt
echo "Built build/M8TP-GTA-Map-unsigned.ipa — re-sign with AltStore or SideStore before installing."
