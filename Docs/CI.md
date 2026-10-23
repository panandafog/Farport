# Continuous Integration

`.github/workflows/build.yml` follows the neighboring Anomaly Merge project's
unsigned macOS build approach, with additional Harbor-specific checks.

## Jobs

- **Lint and Package Tests** installs SwiftLint and tmux, creates a disposable Python
  environment with the pinned AsyncSSH dependency, and runs the full Swift package
  suite through `Scripts/ssh_fixture.py --tmux --run-tests`. The fixture binds only
  loopback and generates temporary keys/files; it stops its own servers afterward.
- **Build macOS (Debug/Release)** regenerates the checked-in project and requires
  no tracked diff, then builds the app and embedded Finder extension without signing.

Package tests run on `macos-15`; Debug/Release app builds run on `macos-26`, with
Xcode 26.3 explicitly selected in both jobs. Build-host and app deployment target
are independent: the app still targets macOS 15 and both CPU architectures.
The newer build host avoids the macOS-15 Icon Composer/asset-distillation failure
scenario. The reported Debug failure ended at `CompileAssetCatalogVariant` without
its underlying actool diagnostic, so the exact original cause remains unconfirmed.
Similar macOS-15 failures loading newer AVFCore/CoreMedia symbols during Icon Composer
compilation are recorded in [Kaset's build script](https://github.com/sozercan/kaset/blob/main/Scripts/build-app.sh).
Do not skip the icon/accent assets or silently replace failed compilation with
prebuilt resources. Toolchain inventories: [macOS 15](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md),
[macOS 26](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
Review the selected Xcode path when updating the runner. Homebrew installs SwiftLint
and tmux; XcodeGen is installed separately through `Scripts/xcodegen.sh`.

## Reproducible Project Generation

Use `sh Scripts/xcodegen.sh generate` locally and in CI. It downloads the official
[XcodeGen 2.44.1 release](https://github.com/yonaskolb/XcodeGen/releases/tag/2.44.1),
verifies its pinned SHA-256, and keeps the binary and bundled setting presets in
ignored `Build/Tools/XcodeGen/2.44.1`. It neither uses nor changes the Homebrew copy.
The first invocation needs GitHub access; subsequent invocations use the local copy.

An unpinned Homebrew install on the runner generated a different project, including
string-valued `SystemCapabilities` instead of dictionaries. Keep the generated-file
diff check: it catches drift, not just compilation errors. To upgrade XcodeGen,
change the version and verified release digest together, regenerate locally, and
review the generated diff before committing. Do not normalize away capability/type
differences or relax this check just to accept a new generator's output.

Events: push/PR targeting `main` or `dev`, plus manual dispatch. The token is
read-only, checkout does not retain credentials, and there are no repository secrets,
Apple accounts, distribution uploads, or production server connections. Fork PRs
run with `pull_request`, never privileged `pull_request_target`.

Keep the root `Package.resolved` in Git. Both jobs disallow silently resolving new
versions. Before building, CI also copies it to the Xcode workspace's
`xcshareddata/swiftpm/Package.resolved` path: the pinned Xcode toolchain may look
there rather than use the root package's lockfile directly. This copy exists only
in the disposable runner checkout; update the root lockfile, not two independent
version lists. See [Apple's package CI guidance](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows).
Vendored Citadel sources and their license/patch notes must remain tracked.

## Limits

Unsigned app builds are compilation checks, not runnable release artifacts. They
cannot validate Keychain access groups, File Provider registration, CloudKit accounts,
Local Network prompts, provisioning, notarization, or App Store acceptance.
Hosted macOS tests require a properly signed app and matching capability profiles;
run these locally using the `Harbor` test scheme and an isolated library, then rebuild
normally to remove test-only signing exceptions. No signing material belongs in Git.

Before a release, complete [TestFlight preparation](TestFlight.md), run the signed
hosted suite, and manually verify the system integrations. Build output is captured
in full with `tee` and `pipefail`, so a failed compiler cannot turn into a successful
step. On failure, CI retains `build.log` and the build `.xcresult` in a configuration-
and attempt-specific diagnostics artifact for seven days. It publishes neither app
bundles nor test data. Inspect the first actool error there, not just xcodebuild's
final failed-command summary. The job also logs host OS, Xcode version, and commit.
