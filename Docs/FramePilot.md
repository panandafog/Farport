# FramePilot integration

FramePilot is a local tool from `../FramePilot`, not a dependency shipped inside
Farport. This integration uses Debug-only, offline screenshot scenes. Public demo
servers are visible in the library but are never selected or contacted by scenes.
Real hosts, credentials, server pins, iCloud and Finder domains are not loaded.

## Prepare

From the Farport repository:

```sh
sh Scripts/xcodegen.sh generate
sh Scripts/prepare-terminal-build.sh
sh Scripts/framepilot.sh prepare
```

The terminal preparation checks SwiftTerm's Metal toolchain (downloads it if missing).
The last command builds the sibling CLI and asks it to inspect Farport and the
installed simulators. It writes four complete configs, with this Mac's absolute
paths and current simulator IDs:

```text
Build/FramePilot/ios-light.json
Build/FramePilot/ios-dark.json
Build/FramePilot/macos-light.json
Build/FramePilot/macos-dark.json
```

These machine-local configs, the tool build and all generated captures are ignored
by Git. Re-run prepare after moving the repositories or changing simulators. It
does not boot a simulator, launch Farport, discover/run UI tests or capture a screen.
Override `FRAMEPILOT_ROOT` if the sibling repository is elsewhere, or provide an
existing `FRAMEPILOT_CLI` executable. No global CLI installation is required.

## Capture explicitly

```sh
sh Scripts/framepilot.sh capture ios-light
sh Scripts/framepilot.sh capture ios-dark
sh Scripts/framepilot.sh capture macos-light
sh Scripts/framepilot.sh capture macos-dark
```

In FramePilot's graphical app, load one of the generated JSON configurations. The
CLI and GUI use the same engine/configuration. Results are written into unique
folders under `Build/FramePilot/Runs`, including `run.json`, logs and exported PNGs.
Languages are English and Russian. Each preset captures one appearance; iOS uses
the appearance of the disposable simulator, macOS uses the test-selected window
appearance without saving a preference. Screenshot scenes always use the default
terminal palette and follow appearance, without changing the user's saved preferences.

FramePilot creates/disposes its own iPhone/iPad simulators. The prepare step chooses
its recommended available devices; the JSON device list can be edited before capture.
If FramePilot's model-name list omits a newer iPhone, preparation reads the installed
Apple simulator profile and adds an available iPhone only when its pixel dimensions
match a primary size accepted by FramePilot (currently including 1320×2868). It does
not create or boot a simulator and does not change the sibling tool. If no suitable
iPhone is available, preparation fails with instructions rather than silently making
an iPad-only set.
Do not use a physical review device or a live SSH server to generate screenshots.

## Scenes and readiness

| Argument value | Content | Platforms |
| --- | --- | --- |
| `hosts` | Host library | macOS, iOS/iPadOS |
| `terminal` | Production API, Shell tab with sample commands | macOS, iOS/iPadOS |
| `logs` | Production API, Logs tab | macOS, iOS/iPadOS |
| `host-settings` | Native host editor with a fictional profile | macOS, iOS/iPadOS |
| `files` | Connected in-memory SFTP browser | macOS |

FramePilot launches with `--screenshot-scene=<value>`; `--demo` is not additionally
required. Screenshot arguments take the isolated Debug demo path, even if the
value is invalid. Invalid/unsupported scenes report an error and do not create a
readiness marker. `HARBOR_ISOLATED_TESTS=1` still has priority and disables the scenes.
Release ignores all screenshot arguments. No runtime switch exists in TestFlight.

Terminal scenes deliver their complete initial output before reporting connected,
use a steady cursor, and do not automatically open the iOS software keyboard.
On compact iPhone, terminal scenes select the detail column and hosts selects the
sidebar. No navigation taps, external services or asynchronous remote output are needed.
The prepared content exposes `screen.<value>` accessibility identifiers only after
the relevant terminal/files are ready; host settings uses the actual editor form.

## macOS capture adapter

FramePilot currently supports macOS only through XCTest attachments. The dedicated
`Farport Screenshots` scheme and `FarportScreenshots/StoreScreenshots` target provide
ten small capture methods: five scenes × light/dark. These are capture adapters,
not part of the normal Farport test scheme or CI. FramePilot's presets select just
the matching five methods. Attachments use `framepilot-<scene>-<appearance>` and
`keepAlways`; no external helper or FramePilot package is needed in the test target.

The Debug scene sets its own window frame to 1280×800 points, including the title
bar, and centers it. At 1×/2× this targets 1280×800 / 2560×1600 pixels. The capture
adapter waits for readiness and the frame size, then captures that application's
window. Confirm exported dimensions in FramePilot after the first actual run;
this integration's preparation does not establish visual correctness.

Actual macOS capture requires an unlocked GUI session and may request UI Automation
permission. FramePilot's runner launches/terminates Farport, so finish active work
and close your regular Farport before starting that capture. Preparation/build-only
checks do not launch or terminate the application.

Build the capture adapter without running it:

```sh
xcodebuild -project Farport.xcodeproj -scheme 'Farport Screenshots' \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath Build/FramePilot/Verification CODE_SIGNING_ALLOWED=NO build-for-testing
```
