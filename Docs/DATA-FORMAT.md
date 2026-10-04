# Dataset v1, optional v2 metadata

Root fields: schemaVersion (1), id, mapID, title, coordinateSpace (normalized-image-v1), source, isDemo, categories, markers. Optional generatedAt and validUntil must be ISO-8601 timestamps such as 2026-10-04T06:00:00Z. Use future validUntil for a live feed.

Categories: id, title, symbol (SF Symbol), color (six hex digits), optional group, summary and cadence. cadence daily opts into 06:00 UTC completion rollover. Static and seasonal categories do not reset automatically. Category IDs are unique; personal is reserved for user pins.

Markers: id, categoryID, title, x, y, details, optional guideURL and imageURL (HTTPS only). Stable IDs preserve completion across same-dataset updates.

Coordinates are normalized from the top-left of the final image. x = pixelX/imageWidth, y = pixelY/imageHeight, both finite in [0,1]. Different map extents are not interchangeable.

Bundled v2: dataset ID gta-online-community-v2, map ID gtav-community-8192-v1. Community source projection extent [0, -8192, 8192, 0]: x=source.lng/8192, y=-source.lat/8192. The bundled satellite image is 2048x2048 with no crop. This is not a generic world XYZ transform. See community-provenance.json.

Legacy v1: map ID gtav-atlas-v1, atlas 1375x1375 after the crop recorded in map-provenance.json. Do not move legacy personal coordinates onto the v2 image.

Maximum dataset 20 MB / 200 categories / 20,000 markers. Personal markers up to 5,000. Routes up to 300 unique known marker IDs. Backups up to 70 MB, with active snapshot and optional base64 imported image. Optional v2 snapshot fields (route IDs, exclusions, appearance, feed URL, reset key, profile name) decode as absent when loading old backups.

The feed client is opt-in HTTPS only. Dataset and map IDs must match the active dataset; undated/expired live feeds are rejected before installation. Generated data must actually be maintained by your provider; adding a future timestamp alone does not establish factual freshness. The app does not connect to a built-in GTAWeb API.

Switching datasets needs a backup if you want to preserve the current active state. Same ID and map ID updates keep surviving marker IDs, personal pins and route state. A feed update cannot silently switch map projections. Imported photos and guides load from their external providers when opened.

Docs/dataset-template.json illustrates the original schema without invented coordinates; set its mapID and id to the correct source before adding data. The bundled demo remains explicitly synthetic and does not represent GTA locations.
