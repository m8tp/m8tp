# M8TP GTA Map v2

Native SwiftUI iOS companion with a UIKit pan/zoom map engine, iOS 17+. Open M8TPGTAMap.xcodeproj. Arabic setup guide: README-AR.md.

## Included

Full-screen map UI, floating search, category sheets, clustered markers, favorites, per-category counters and completion/reset actions, 933 community coordinate records across 38 populated sections, 290 externally hosted photo links, personal pins, local profile name, deep-link sharing, persisted direct-line route planning/reordering, category route exclusions, optional validated dated JSON feeds, 06:00 UTC daily completion rollover, backup/import/export and v1 pin preservation.

The satellite image matches the coordinate source's [0, -8192, 8192, 0] extent. See Docs/community-provenance.json. Factual coordinates/names/media URLs are extracted; no third-party source code or popup descriptions are copied. Original photo hosts retain their attribution. Game imagery belongs to Rockstar Games.

## Exact parity status

This is not a complete GTAWeb clone. See Docs/FEATURE-PARITY.md for the specific gaps: no bundled pumpkin positions, full GTAWeb database, live daily provider, GTAWeb account sync, Cayo Perico map, six original map styles or live weather. Empty sections are labeled as requiring data. Satellite, Night contrast and High contrast are visual treatments of one image, not distinct source map layers.

## Build

Use Codemagic workflow ios-unsigned or GitHub Actions workflow Build iPhone IPA. Both build the unsigned **device** IPA, then build and launch a simulator app and capture a native screenshot. No signing credentials are needed during the unsigned cloud build. Re-sign the resulting IPA before installing.

Local macOS commands:

```bash
bash scripts/build-unsigned-ipa.sh
bash scripts/smoke-simulator.sh
```

Portable checks:

```bash
python3 scripts/validate_project.py
bash -n scripts/build-unsigned-ipa.sh
bash -n scripts/smoke-simulator.sh
```

The edited v2 app has not been compiled or run in the preparation environment. Portable syntax/project checks do not prove native compilation or device behavior. CI model checks and simulator smoke tests are configured but have not been executed here.

The smoke check verifies native UI entry, the bundled 933-marker dataset and a decoded map; it does not test every user interaction or coordinate in the game. Review the generated simulator PNG, then test touch, sheets, photos, route editing, backup and relaunch on your device.

Keep the existing bundle ID com.m8tp.gtamap to preserve app identity. v1 empty catalog states are backed up before installing community data. Restore them on their original atlas through Data; imported datasets are not automatically overwritten.
