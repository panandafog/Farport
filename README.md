# Harbor

A native macOS SSH and SFTP client with saved hosts, terminal tabs, ProxyJump,
optional persistent tmux sessions, and Finder integration.

## Features

- Interactive terminals with system light/dark appearance and retained output after disconnect.
- Named terminal tabs and local workspace restoration; optional tmux reconnect.
- SFTP browsing, uploads/downloads, progress, cancellation, and basic file operations.
- Optional read-only or read/write Finder locations using File Provider.
- Native multi-hop ProxyJump for SSH, SFTP, and Finder.
- Keychain credentials and explicit server-key fingerprint verification.
- Opt-in iCloud host-profile sync. Credentials and server-key trust stay on the device.

## Requirements

- macOS 15 or newer.
- Xcode 26.3 or newer, including Icon Composer support; locally validated with Xcode 27.
- SwiftLint (`brew install swiftlint`). The pinned XcodeGen wrapper is needed only for regeneration.
- Apple Development signing with matching App Group, Keychain, CloudKit, and Push capabilities.

iOS/iPadOS clients and additional file protocols are planned, not included.

## Run

Open `Harbor.xcodeproj`, select **Harbor > My Mac**, and press **Command-R**.
The first build downloads Swift Package dependencies. Select your own signing Team
if needed; capability setup is described in [iCloud](Docs/iCloud.md) and [Finder](Docs/Finder.md).
Do not rename existing App Group or Keychain identities when updating this installation.

```sh
brew install swiftlint
xcodebuild -project Harbor.xcodeproj -scheme Harbor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath Build -allowProvisioningUpdates build
open Build/Build/Products/Debug/Harbor.app
```

Use **HarborLocal** to develop without CloudKit provisioning; it still needs signing
for shared Keychain and Finder access. For Local Network permissions and the manual
**Harbor Attach** fallback, see [Debugging](Docs/Debugging.md).

`project.yml` is the XcodeGen source of truth. The generated project and dependency
lockfile are included. After configuration/resource changes, run `sh Scripts/xcodegen.sh generate`.
The wrapper downloads the official XcodeGen 2.44.1 binary and presets into `Build/Tools`,
checks the pinned SHA-256, and uses the same tool locally and in CI; it does not modify Homebrew.
`AppIcon.icon` is a temporary copy of the MediaPlayer/Trackfold icon, to be replaced
before public distribution.

## Checks

```sh
sh Scripts/lint.sh
swift test
xcodebuild -project Harbor.xcodeproj -scheme Harbor \
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

GitHub Actions runs strict SwiftLint, the package suite with this fixture, and unsigned
Debug/Release app builds on pushes to `main`/`dev` and pull requests. It needs no
Apple credentials and does not upload to TestFlight. Hosted AppKit/Keychain tests
remain a separate signed local check. See [CI](Docs/CI.md).

## Status

This is a development MVP, not yet a TestFlight release. The main app is currently
unsandboxed. Distribution signing, sandbox migration, CloudKit production setup,
export compliance, and release validation remain on the [TestFlight checklist](Docs/TestFlight.md).
An unsigned CI build is not an installable or distribution-validated release.

No SSH agent or `~/.ssh/config` import, recursive deletion, resumable transfers,
or on-disk terminal scrollback yet. Finder uses asynchronous File Provider caching,
not a synchronous mounted SFTP disk. Persistent remote history requires server-side tmux.

## Documentation

- [Usage and implementation](Docs/Usage.md)
- [Security and storage](Docs/Security.md)
- [Finder access and limits](Docs/Finder.md)
- [ProxyJump](Docs/ProxyJump.md)
- [Session recovery](Docs/SessionRecovery.md)
- [iCloud](Docs/iCloud.md)
- [Contributor guide](AGENTS.md)

SSH/SFTP uses vendored [Citadel](https://github.com/orlandos-nl/Citadel) with documented
patches; the terminal uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
Third-party sources retain their own licenses.
