# Farport

A native SSH client for macOS, iPhone and iPad with saved hosts, terminal tabs,
ProxyJump and optional persistent tmux sessions. macOS also includes SFTP and Finder integration.

## Features

- Interactive terminals with system light/dark appearance and retained output after disconnect.
- Named terminal tabs and local workspace restoration; optional tmux reconnect.
- macOS SFTP browsing, uploads/downloads, progress, cancellation, and basic file operations.
- Optional macOS read-only or read/write Finder locations using File Provider.
- Native multi-hop ProxyJump for SSH, SFTP, and Finder.
- Keychain credentials and explicit server-key fingerprint verification.
- Opt-in iCloud host-profile sync. Credentials and server-key trust stay on the device.
- English and Russian interface, connection prompts and application error messages.

## Requirements

- macOS 15 or newer.
- iOS/iPadOS 17 or newer for the terminal-only mobile app.
- Xcode 26.3 or newer, including Icon Composer support; locally validated with Xcode 27.
- SwiftLint (`brew install swiftlint`). The pinned XcodeGen wrapper is needed only for regeneration.
- Apple Development signing with matching App Group, Keychain, CloudKit, and Push capabilities.

The mobile app uses standard SwiftUI navigation, lists, forms and menus with a UIKit
terminal. It shares session, library, storage and transport logic with macOS. File
browsing is macOS-only; additional protocols remain planned.

## Run

Open `Farport.xcodeproj`, select **Farport > My Mac**, and press **Command-R**.
The first build downloads Swift Package dependencies. Select your own signing Team
if needed; capability setup is described in [iCloud](Docs/iCloud.md) and [Finder](Docs/Finder.md).
Do not rename existing App Group or Keychain identities when updating this installation.

```sh
brew install swiftlint
xcodebuild -project Farport.xcodeproj -scheme Farport \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath Build -allowProvisioningUpdates build
open Build/Build/Products/Debug/Farport.app
```

Use **FarportLocal** to develop without CloudKit provisioning; it still needs signing
for shared Keychain and Finder access. For Local Network permissions and the manual
**Farport Attach** fallback, see [Debugging](Docs/Debugging.md).

For iPhone/iPad select **Farport iOS** and an iOS device or Simulator. **Farport iOS Local**
omits CloudKit/push entitlements for local development. Both use the existing bundle ID
`com.panandafog.harbor`; signing for a physical device still needs a matching iOS profile.
See [iOS development](Docs/iOS.md) for lifecycle, test isolation and device checks.

`project.yml` is the XcodeGen source of truth. The generated project and both dependency
lockfiles (shared package and Xcode app) are included. After configuration/resource
changes, run `sh Scripts/xcodegen.sh generate`.
Change version/build numbers in `project.yml` (`MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION`), not only in Xcode. Regenerate before committing any
project or scheme changes; CI checks that the generated files match exactly.
The product, project, schemes, package and modules use Farport names.
Bundle IDs, Keychain/App Group/iCloud identities, saved-data paths,
and existing tmux session names are unchanged by the rename.
The wrapper downloads the official XcodeGen 2.44.1 binary and presets into `Build/Tools`,
checks the pinned SHA-256, and uses the same tool locally and in CI; it does not modify Homebrew.
`AppIcon.icon` is a temporary copy of the MediaPlayer/Trackfold icon, to be replaced
before public distribution.

## Checks

```sh
sh Scripts/lint.sh
swift test
sh Scripts/verify-ios.sh
xcodebuild -project Farport.xcodeproj -scheme Farport \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath Build test
```

`swift test` skips network tests unless the disposable SSH/SFTP fixture is running.
For full package coverage, including ProxyJump and tmux recovery:

```sh
brew install tmux
python3 -m venv /private/tmp/harbor-test-env
/private/tmp/harbor-test-env/bin/pip install -r Scripts/requirements-test.txt
/private/tmp/harbor-test-env/bin/python Scripts/ssh_fixture.py --tmux --run-tests
```

GitHub Actions runs strict SwiftLint, the package suite with this fixture, iOS shared-module
compilation and unsigned Debug/Release app builds on pushes to `main`/`dev` and pull requests. It needs no
Apple credentials and does not upload to TestFlight. Hosted AppKit/Keychain tests
remain a separate signed local check. See [CI](Docs/CI.md).

## Status

This is a development MVP, not yet a TestFlight release. The main app and Finder
extension use App Sandbox. Distribution signing, CloudKit production setup,
export compliance, and release validation remain on the [TestFlight checklist](Docs/TestFlight.md).
An unsigned CI build is not an installable or distribution-validated release.

No SSH agent or `~/.ssh/config` import, recursive deletion, resumable transfers,
or on-disk terminal scrollback yet. Finder uses asynchronous File Provider caching,
not a synchronous mounted SFTP disk. Persistent remote history requires server-side tmux.

## Documentation

- [Usage and implementation](Docs/Usage.md)
- [Shared architecture and localization](Docs/Architecture.md)
- [iPhone and iPad](Docs/iOS.md)
- [Security and storage](Docs/Security.md)
- [Finder access and limits](Docs/Finder.md)
- [ProxyJump](Docs/ProxyJump.md)
- [Session recovery](Docs/SessionRecovery.md)
- [iCloud](Docs/iCloud.md)
- [Contributor guide](AGENTS.md)

SSH/SFTP uses vendored [Citadel](https://github.com/orlandos-nl/Citadel) with documented
patches; the terminal uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
Third-party sources retain their own licenses.
