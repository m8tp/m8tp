#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild -project M8TPGTAMap.xcodeproj -scheme M8TPGTAMap \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/SimulatorDerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl list runtimes -j > build/runtimes.json
xcrun simctl list devicetypes -j > build/devicetypes.json
RUNTIME_ID="$(python3 - <<'PY'
import json
r=[x for x in json.load(open('build/runtimes.json'))['runtimes'] if x.get('isAvailable') and 'iOS' in x['name']]
if not r: raise SystemExit('No iOS simulator runtime is installed')
print(max(r,key=lambda x:tuple(map(int,x['version'].split('.'))))['identifier'])
PY
)"
DEVICE_TYPE="$(python3 - <<'PY'
import json
types=json.load(open('build/devicetypes.json'))['devicetypes']
matches=[x for x in types if x['identifier'].endswith('.iPhone-16')]
if not matches: matches=[x for x in types if 'iPhone' in x['name']]
if not matches: raise SystemExit('No iPhone simulator device type is installed')
print(matches[0]['identifier'])
PY
)"
DEVICE_ID="$(xcrun simctl create M8TP-Smoke-Test "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl delete "$DEVICE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b
APP="build/SimulatorDerivedData/Build/Products/Debug-iphonesimulator/M8TPGTAMap.app"
xcrun simctl install "$DEVICE_ID" "$APP"
SIMCTL_CHILD_M8TP_SMOKE_TEST=1 xcrun simctl launch "$DEVICE_ID" com.m8tp.gtamap
CONTAINER_PATH="$(xcrun simctl get_app_container "$DEVICE_ID" com.m8tp.gtamap data)"
for attempt in {1..30}; do
  if test -f "$CONTAINER_PATH/Documents/smoke-ready.json"; then break; fi
  sleep 1
done
cp "$CONTAINER_PATH/Documents/smoke-ready.json" build/smoke-ready.json
python3 - <<'PY'
import json
r=json.load(open('build/smoke-ready.json'))
assert r['markerCount'] == 933, r
assert r['imageLoaded'] and not r['isDemo'], r
assert r['datasetID']=='gta-online-community-v2', r
print('Simulator startup verified: native UI entered, community data and map loaded.')
PY
xcrun simctl io "$DEVICE_ID" screenshot build/M8TP-GTA-Map-preview.png
