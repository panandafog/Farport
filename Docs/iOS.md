# iPhone And iPad

The first mobile version supports saved hosts, SSH terminals, password/private-key
authentication, ProxyJump, server-key verification, terminal tabs, tmux and opt-in
iCloud profile sync. Files and Finder are not part of the mobile UI.

## Build

Open Farport.xcodeproj and select **Farport iOS** with an iPhone/iPad destination.
Minimum iOS/iPadOS is 17. **Farport iOS Local** omits CloudKit and push capabilities;
it does not pretend to sync. The bundle identifier remains `com.panandafog.harbor`.
Device signing needs an iOS provisioning profile authorizing the existing Keychain
group and, for the normal scheme, `iCloud.com.panandafog.harbor` plus push notifications.
The macOS profile cannot substitute for an iOS profile.

```sh
sh Scripts/xcodegen.sh generate
sh Scripts/verify-ios.sh
xcodebuild -project Farport.xcodeproj -scheme 'Farport iOS Local' \
  -configuration Local -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -derivedDataPath Build/iOSApp -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation test
```

Choose an installed Simulator name for the test command. Test schemes set
`HARBOR_ISOLATED_TESTS=1`: startup uses empty memory repositories, no real Keychain,
cloud account or persisted library. Never use a user's server to test disconnects.
The verification script prepares Apple's Metal Toolchain and enables the reviewed,
exact-pinned SwiftTerm build-info plugin for CLI builds. IDE builds need the standard
package-plugin trust confirmation; see [Terminal](Terminal.md).

## Interface And Lifecycle

NavigationSplitView collapses to a navigation stack on iPhone and narrow iPad windows.
Lists, forms, menus, sheets, alerts and document import are native controls. The shared
host editor hides its file settings on iOS. SwiftTerm supplies text input, selection,
scrollback, hardware-key handling and a software-keyboard accessory with terminal keys.
The terminal follows system appearance while retaining ANSI attributes and its buffer.
Links require confirmation and only HTTP(S) URLs can open. Remote OSC 52 writes are
not allowed to overwrite the mobile clipboard; explicit Copy remains available.

MobileAppRoot loads the library in its appearance task, not during the initial SwiftUI
body evaluation: restoring hosts also constructs UIKit terminal views. The loading
state is visible until that model is installed. Lifecycle events are handled by this
root after loading, and repeated view updates must not reload the library.

Hosts and workspace metadata use the same protected repository formats as macOS,
inside the mobile app's own Application Support directory. Secrets and server pins
stay in the device Keychain. iCloud sync transfers profiles only; imported hosts need
credentials and trust to be configured on each device. Workspace and scrollback do
not sync through iCloud. Restoration never starts a connection automatically.

An inactive scene saves workspace metadata without interrupting a permission dialog.
On background, transports are closed and local terminal history stays in memory.
Foreground reattaches previously connected tmux sessions; standard SSH remains
disconnected until the user reconnects. App termination loses local scrollback, but
tab UUIDs remain stable so tmux can restore the remote screen. Only one mobile scene
is enabled. No background audio, location or other unrelated execution entitlement
is used to keep SSH alive.

## Verification

Shared tests cover route changes, persistence failure, credential import, background
detach and foreground tmux recovery without replay. iOSTests covers native output
retention, input gating, theme changes and phone/tablet layouts. CI builds shared
libraries and unsigned device Debug/Release apps; it does not upload to TestFlight.
The hosted mobile tests compile the production UIKit adapter and terminal screen directly,
with an injected test transport. They do not import the app composition module or link a
second SSH/Crypto graph. Host-library behavior is tested separately in FarportSessionsTests.

For manual Simulator UI checks, Debug `--demo` uses synthetic output and memory-only
hosts. Debug Simulator `HARBOR_TEST_PORT` connects to the disposable loopback SSH
fixture with its known test credentials, still requiring explicit server-key trust.
Neither mode is included in Release. Normal launches use protected persistent storage.

The iOS Info.plist declares `UIBackgroundModes = [remote-notification]` for CloudKit
silent pushes. This is not permission for persistent background SSH. Keep this key in
project.yml; regenerating the project must not remove it. MobileLibraryTests checks
the built host application's plist and renders the complete startup root with empty
and restored libraries, rather than testing only the terminal screen.

Validation on 2026-10-25: all 131 package tests passed with the disposable SSH/tmux
fixture, alongside 7 mobile hosted tests (iOS 27) and 44 isolated macOS hosted tests. Unsigned
iOS Debug/Release and macOS Debug builds passed, as did strict SwiftLint and the
checkout-name-independent project generation check.

Manual iPhone/iPad Simulator checks covered adaptive navigation, English/Russian
forms, terminal input, explicit server trust, disconnect with retained output,
background/foreground tmux reattachment, appearance changes and iPad rotation.
The keyboard control moved to the navigation toolbar to avoid overlapping the
terminal accessory. The final icon-only editor Save/Cancel adjustment is compiled,
but its last visual recheck was blocked by the locked Mac.

The subsequent physical-iPhone white-screen report is not considered closed by the
Simulator tests alone. CloudKit's missing background-mode declaration is fixed and
startup now defers UIKit-backed library creation; confirm a normal launch on the
affected device without deleting its app data.

Physical-device validation is still required for signing, Keychain groups, CloudKit
account/push behavior, hardware keyboards and real background timing. Local Network
privacy cannot be validated in Simulator; see Apple's
[TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
