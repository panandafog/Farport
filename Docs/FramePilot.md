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

## Capture status (2026-11-02)

### Latest capture retry

After unlocking the Mac, Device Hub responded normally. The guided Duo light run
`Build/FramePilot/Runs/2026-11-02T03-07-32Z-A252CEC3` completed all 16 images with
zero errors: Closed/Open displays, four scenes and English/Russian. Representative
exports were visually checked for rendered content and localization. Closed images
are 1398×2034; Open images are 2853×2007. Native pixels are preserved. FramePilot's
current primary App Store size list warns about these Duo sizes; that warning does
not establish whether App Store Connect accepts them in a particular screenshot slot.

The matching dark run, `Build/FramePilot/Runs/2026-11-02T03-32-52Z-E9D6B471`,
also completed 16 images with zero errors. The full Duo matrix is now verified:
32 PNGs across two displays, two appearances, two languages and four scenes.
Selected PNGs are in `AppStore/screenshots/iPhone-Duo/<display>/<language>/<appearance>`;
the combined archive is `Build/FramePilot/Exports/Farport-iPhone-Duo-en-ru.zip`.
Closed/Open preparation still requires Device Hub and explicit confirmation;
automatic posture switching remains future work.

The macOS dark retry, `Build/FramePilot/Runs/2026-11-02T04-06-34Z-A89839BF`,
completed all ten captures with zero errors in an unlocked GUI session. Terminal,
host editor and file-browser exports were visually checked. No activation change
was needed for this successful run; the earlier failure was not reproduced.
Both macOS appearances are now complete: five scenes × two languages × two themes,
20 PNGs at 1280×800 in `AppStore/screenshots/macOS/<language>/<appearance>`.
The combined archive is `Build/FramePilot/Exports/Farport-macOS-en-ru.zip`.

The requested capture sets are complete: 20 macOS, 32 ordinary iPhone/iPad and
32 iPhone Duo images (84 total). The original iOS archive remains at
`Build/FramePilot/Exports/Farport-iOS-iPhone-iPad-en-ru.zip`.

All 84 selected PNGs were moved from ignored `Build/FramePilot/Exports` into
[`AppStore/screenshots`](../AppStore/screenshots/README.md) alongside the metadata
so they can be committed. Ordinary mobile images are under
`AppStore/screenshots/iOS/<family>/<language>/<appearance>`. SHA-256 checks confirmed
the move preserved every image byte. Build output, raw runs and ZIP archives stay
ignored; `.gitignore` does not exclude these selected App Store PNGs.

The successful retry uses an ignored source snapshot at
`/private/tmp/farport-capture-20261102/Farport`, copied from the current working tree
without accumulated build output, and local `*-retry.json` configs. This avoids
project discovery traversing the large capture/build directory. No application
source, real host library, Keychain or iCloud data was changed. Existing ordinary
iPhone/iPad and macOS light exports are preserved.

The notes below retain the earlier failures and implementation history.

### Verified captures and build fix

- iPhone 18 Pro Max: 1320×2868, four scenes × two languages × two appearances.
- iPad Pro 13-inch (M5): 2064×2752, the same matrix. Total: 32 successful iOS captures.
- macOS: five scenes × two languages in light appearance, 1280×800. Total: 10 captures.
- Local ZIPs: `Build/FramePilot/Exports/Farport-iOS-iPhone-iPad-en-ru.zip` and
  `Build/FramePilot/Exports/Farport-macOS-light-en-ru.zip`. These outputs are ignored
  by Git and are not available from a fresh checkout.

The missing `SwiftTermBuildInfoGenerator` build input was fixed in the sibling
`../FramePilot/Sources/Core/CaptureEngine.swift`: remove global `-sdk iphonesimulator`
from the build/settings command and select the simulator using `-destination`.
Swift Package build-tool executables need the host macOS SDK. The sibling README
documents this too. At this checkpoint these two FramePilot edits are uncommitted;
preserve its unrelated pre-existing workspace/project-selection edits.
Rebuild the CLI through `sh Scripts/framepilot.sh …` after changing FramePilot;
direct execution of an older CLI binary will not include source fixes.

### iPhone Duo display support (2026-11-02)

FramePilot now accepts an optional per-device `displays` array, for example
`"displays": ["primary", "primary-1"]`. Omit it for the previous automatic behavior.
The GUI exposes comma-separated display selectors under each selected device in
Scenes mode, with an “Оба дисплея Duo” shortcut. Selection survives config reload,
project inspection and run-history reuse. XCTest attachments remain controlled by
the tests; explicit display selection is rejected in UI-test configs.

Each display is a separate capture job with its own disposable simulator, output
folder and artifact identity. All stability samples and the export use the same
`simctl io … screenshot --display=…` selector. Native sizes and App Store size
warnings are preserved. Invalid display choices are checked before the scene loop.
A fully black selected-display frame is treated as an inactive display, not a
successful screenshot; remaining scenes for that display are skipped.

`prepare` now generates `ios-duo-light.json` and `ios-duo-dark.json` when an
available Duo is installed, using its actual runtime from `simctl list`. The wrapper
accepts these presets and enables `--interactive` for Duo. They request both
`primary` and `primary-1`. Run them from an interactive terminal; headless CLI
capture without a preparation handler fails before building rather than producing
an inactive-display screenshot.

Real-device-type smoke verification used isolated clones of
`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo` with installed runtime
`com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`:

- `primary` / LCD / ID 1: Farport `hosts` rendered correctly, 1398×2034.
- `primary-1` / LCD-1 / ID 3: PNG was 2007×2853 but entirely black.
- The original smoke run, before black-frame rejection was added, reported two
  exports without errors. Its second export is **invalid**. Do not count it as a
  completed Duo capture set.
- Diagnostic `screenConfig power off/on` on another disposable clone did not
  activate the second screen and was followed by SpringBoard launch failures.
  This workaround was **not** added to FramePilot.

Local evidence: `/private/tmp/FramePilotDuoSmoke/2026-11-01T22-49-52Z-19AC1B6E`
(`run.json`, command traces, both PNGs). Temporary diagnostic simulators were removed.
After unlocking the Mac, the GUI check identified Xcode 27's **Device Hub**
(`com.apple.dt.Devices`) and its **Closed / Partially Open / Open** controls.
Setting **Open** activated `primary-1`; a real Farport `hosts` image rendered
correctly at native size. The command-line tools' available help does not expose
an equivalent hinge/posture setter. No private framework dependency or screen-power
workaround was added.

FramePilot now requests posture preparation before each Duo display job. In the
GUI it shows the temporary simulator's exact name/UDID and a **Дисплей готов —
продолжить** button. In the CLI, `--interactive` prints the same instruction and
waits for Enter. Select **Closed** for `primary`, **Open** for `primary-1`, wait
for the display, then confirm. After preparation all scenes/languages for that
job run automatically. Waiting is bounded to ten minutes and cancellable; temporary
simulator cleanup still runs. Fully automatic posture switching remains future work.

Guided CLI smoke run:
`/private/tmp/FramePilotDuoGuidedSmoke/2026-11-01T23-20-47Z-EB8E2866`.
The new preparation/continue flow completed both jobs with two exports, no command
errors, and no remaining temporary simulators. The Open export was 2853×2007 and
showed ScreenshotDemo. Its Closed export (1398×2034) was still the app's empty
white frame, so this smoke proves the handoff/export path, **not** a visually
complete two-screen store set. Farport's hosts scene was separately viewed correctly
on Closed in the earlier run and on Open after the GUI posture change
(`/private/tmp/duo-open-ready.png`). Explicit application readiness or longer scene
settling is still needed for cold-launch content; stable pixels alone cannot prove
that an application has finished rendering.


The config-loading UI also had a mode-change observer that could replace saved
Duo selection with the recommended iPad after inspection. Picker actions now run
only for user edits, preserving imported mode/device/display choices.

A real `prepare` attempt previously timed out in `xcodebuild -list -json` after
180 seconds. Config generation was checked with controlled simulator inventory,
and the existing local Duo JSONs were updated with both display selectors. The
full 32-image Farport matrix is not yet verified. Existing user simulators and
Farport host/credential/cloud data were not modified.

Follow-up Farport verification (2026-11-02): 14 display/workspace model tests passed,
the CLI rebuilt, and both preset scripts passed syntax checks. Local Duo presets
used 15 seconds of settling to allow cold-launch content to appear. The real run
`Build/FramePilot/Runs/2026-11-01T23-39-58Z-D721EBAA` then failed before simulator
creation: the post-build `xcodebuild -showBuildSettings -json` query exceeded its
120-second timeout for both display jobs. No images were produced and posture
preparation was not reached. The second job repeated the failed build/settings
stage because no product was cached after the first failure. Next investigate this
metadata query in FramePilot's `CaptureEngine.build`: allow sufficient time or
avoid repeating it by reusing validated product metadata. This timeout is separate
from display selection/readiness; the complete Duo matrix and macOS dark captures
remain pending. The run was stopped without further capture attempts.

FramePilot follow-up fix (2026-11-02): the post-build settings query now allows
600 seconds. A failed build/settings preparation is remembered for its SDK for
the rest of that run: subsequent Duo displays and iPad jobs skip preparation and
simulator creation instead of retrying the same iOS build. Independent platforms
can still prepare their own build; a new run retries from scratch. Two engine
regression tests cover timeout/failure sharing across devices/displays, independent
tvOS preparation, persisted results/progress and cancellation. The CLI and macOS
app rebuilt successfully. This change does not establish completion of the Duo
capture matrix.

The real settings-only query was repeated against the failed run's existing
DerivedData with a 600-second limit. It succeeded in **124.9 seconds**, returning
one application target (`com.panandafog.harbor`, `Farport.app`). Local diagnostics:
`/private/tmp/framepilot-duo-settings-600.json` and
`/private/tmp/framepilot-duo-settings-600.stderr`. No simulator or capture was
started by this verification; no new store screenshots were produced.

Capture retry after the settings-timeout fix (2026-11-02):
`Build/FramePilot/Runs/2026-11-02T00-08-30Z-FDA82641` passed build/settings preparation
and reached both interactive display handoffs. Automated Device Hub control became
unusable: selecting the owned temporary Duo was followed by repeated 30/60-second
timeouts while reading its accessibility state. The general app inventory remained
accessible. A direct `simctl io … screenshot --display=primary` probe showed an
active Closed SpringBoard (`/private/tmp/farport-duo-closed-ready.png`), but the CLI
handoffs expired before the guided capture completed. The final manifest has zero
artifacts and two preparation timeouts. This is a GUI/handoff blocker, not the old
120-second build-settings failure. No further capture runs were started.

To resume, use a working Device Hub control surface or have an operator set the
exact temporary clone to Closed/Open and confirm promptly in the interactive CLI
or FramePilot GUI. The display must visibly render before confirmation. Do not
automatically confirm Open or accept a black/empty output. The previously verified
32 ordinary iPhone/iPad images and 10 light macOS images remain the completed sets.

### Earlier macOS dark activation failure (resolved on retry)

The earlier dark run failed before scene capture with:

```text
Failed to activate application … (current state: Running Background)
```

All five tests failed at application activation. Inspect
`Build/FramePilot/Runs/2026-11-01T18-39-44Z-E17F3B89/01-Mac/en-US/Tests.xcresult`
and `test.log` if those local files remain. First reproduce one dark test from the
`Farport Screenshots` scheme in an active, unlocked GUI session with UI Automation
permission. If it persists, investigate app/window activation in
`ScreenshotTests/StoreScreenshots.swift` and `App/ScreenshotWindowSetup.swift`.
The initial UI Automation permission timeout was resolved by user confirmation;
the subsequent activation failure's exact cause was not established. The unlocked
retry recorded above completed all dark scenes in both languages. If activation
fails again, use these diagnostics. Avoid restarting a user's active Farport
sessions without permission.
