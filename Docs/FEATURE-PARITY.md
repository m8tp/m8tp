# GTAWeb comparison — v2

Observed reference: GTA Online / Los Santos / Jack O’ Lanterns, inspected 2026-10-04. This table distinguishes native capability from bundled data and services. No claim of exact feature or content parity is made.

| Reference capability | Native v2 status | Practical limit |
| --- | --- | --- |
| Interactive map, zoom/pan | Implemented | One community satellite extent; v1 atlas for old pins |
| Category groups, search, show/hide | Implemented | 38 populated sections, 9 sections explicitly needing data |
| Mark complete, counters, hide completed | Implemented | Manual local progress, not game synchronization |
| Reset one section / all progress | Implemented | Confirmation before bulk changes |
| Information/photo/guide cards | Implemented | 290 photo URLs; own short descriptions and source links, not original GTAWeb instructions |
| Direct-line route planning | Implemented | 300 stops, nearest-first heuristic; not road navigation or the site's exact optimizer |
| Category inclusion/exclusion from routing | Implemented | Applied when generating/optimizing routes |
| Shared marker links | Implemented | App deep links; recipient needs this app and matching dataset |
| Backup/import/export | Implemented | One active dataset, local files |
| Daily completion reset | Implemented | 06:00 UTC; affects categories explicitly marked daily |
| Live daily positions | Feed client implemented, service absent | No built-in current Gun Van, street dealers, caches, etc. |
| Jack O’ Lanterns | Category only | No bundled pumpkin coordinates; no fake positions |
| Other current seasonal events | Partial category structure | Event activation and full seasonal positions not connected |
| Original six map layers | Not matched | Three appearance treatments of the same satellite image |
| Cayo Perico / other map areas | Not included | JSON/image import can support a separately supplied area |
| GTAWeb login and cloud progress | Not connected | Local profile name and backup only |
| Live GTA clock/weather integration | Not implemented | Daily reset countdown is real UTC time, not an in-game weather simulation |
| Full GTAWeb marker database | Not obtained | Community snapshot contains 933 records and was not tested in-game |
| Ads / external analytics | Omitted intentionally | Native application has no ads/analytics |

Downloading GTAWeb page/source assets from the file environment returned HTTP 403; the public browser page was usable for feature inspection. The project does not bypass the site's controls and does not contain a fabricated API URL. Exact parity requires a documented data source/export for the missing records and live services, plus implementation/verification of the remaining map/account/weather features.
