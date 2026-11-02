# App Store screenshots

Selected PNG exports live here alongside [App Store metadata](../app-store-metadata.md)
and are included in Git. Capture date: 2026-11-01/02. Total: **84 PNGs**.

| Directory | Device / display | Size | PNGs |
| --- | --- | --- | ---: |
| `macOS/<language>/<appearance>` | Mac | 1280×800 | 20 |
| `iOS/iPhone/<language>/<appearance>` | iPhone 18 Pro Max | 1320×2868 | 16 |
| `iOS/iPad/<language>/<appearance>` | iPad Pro 13-inch (M5) | 2064×2752 | 16 |
| `iPhone-Duo/primary/<language>/<appearance>` | iPhone Duo — Closed | 1398×2034 | 16 |
| `iPhone-Duo/primary-1/<language>/<appearance>` | iPhone Duo — Open | 2853×2007 | 16 |

Languages: `en-US`, `ru-RU` (the Russian App Store localization is `ru`).
Appearances: `light`, `dark`.

Scenes are numbered in upload order: `01-hosts`, `02-terminal`, `03-logs`,
`04-host-settings`, and macOS-only `05-files`. Images retain their native resolution;
no resizing or recompression was applied when moving them here.

The screenshots use isolated Debug sample hosts. They contain no real user hosts,
credentials or terminal sessions. The shipping app starts with the normal host library;
review accounts and setup instructions are in the metadata file.

Raw runs, logs, build products and local ZIP archives remain under ignored
`Build/FramePilot`. For future captures, select the finished PNGs from that output
and place them here. Do not copy complete run/build directories into this folder.
See [capture setup and verification](../../Docs/FramePilot.md#capture-status-2026-11-02)
for display preparation and the Duo size-validation limitation.
