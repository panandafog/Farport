# Continuous Integration

`.github/workflows/build.yml` follows the neighboring Anomaly Merge project's
unsigned macOS build approach, with additional Farport-specific checks.

## Jobs

- **Lint and Package Tests** installs SwiftLint and tmux, creates a disposable Python
  environment with the pinned AsyncSSH dependency, and runs the full Swift package
  suite through `Scripts/ssh_fixture.py --tmux --run-tests`. The fixture binds only
  loopback and generates temporary keys/files; it stops its own servers afterward.
  `Scripts/verify-sandbox.swift` also checks Boolean sandbox/network/selected-file
  entitlements and the narrow legacy-data migration manifest without signing credentials.
- **Build macOS (Debug/Release)** regenerates the checked-in project and requires
  no tracked diff, checks generation under different checkout names, then builds the
  app and embedded Finder extension without signing.

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

The pinned generator also derives the root local-package navigator folder's name
and GUID from the checkout basename, not the package manifest name
([upstream implementation](https://github.com/yonaskolb/XcodeGen/blob/2.44.1/Sources/XcodeGenKit/SourceGenerator.swift#L50-L74)).
GitHub checks this repository out as `Harbor`, while local clones may be `Farport`.
The post-generation script canonicalizes only that cosmetic file reference, its
GUID references and object ordering. The actual local package reference (`path: .`),
products, application/storage identifiers and capabilities are unchanged.

Run `sh Scripts/verify-project-generation.sh` after generation changes. This check
snapshots tracked/new non-ignored files into disposable directories named `Farport`,
`Harbor` and `checkout with spaces`, reuses the pinned generator, and compares the
complete generated project, shared schemes, workspace settings and Info.plists.
It is also a CI build step; a display-name workaround must not hide unrelated diffs.

Events: push/PR targeting `main` or `dev`, plus manual dispatch. The token is
read-only, checkout does not retain credentials, and there are no repository secrets,
Apple accounts, distribution uploads, or production server connections. Fork PRs
run with `pull_request`, never privileged `pull_request_target`.

Keep both `Package.resolved` and
`Farport.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` in Git.
They describe different graphs: the package lock contains the shared libraries;
the Xcode lock additionally pins SwiftTerm and its transitive ArgumentParser dependency.
Never copy the root lock over the Xcode lock: doing so drops app-only pins, and
strict dependency resolution correctly fails on a fresh runner. Both CI jobs retain
their strict resolved-version flags and run `xcrun swift Scripts/verify-package-locks.swift`.
This checks identical pins for shared dependencies and exact Xcode package requirements.
Update both graphs intentionally when changing common dependencies; package tests
must not prune or rewrite the Xcode lock. See [Apple's package CI guidance](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows).
Vendored Citadel sources and their license/patch notes must remain tracked.

## Limits

Unsigned app builds are compilation checks, not runnable release artifacts. They
cannot validate Keychain access groups, File Provider registration, CloudKit accounts,
Local Network prompts, provisioning, notarization, or App Store acceptance.
Hosted macOS tests require a properly signed app and matching capability profiles;
run these locally using the `Farport` test scheme and an isolated library, then rebuild
normally to remove test-only signing exceptions. First sandbox launch and migration
require a disposable macOS account, not the user's real library: the test isolation
flag does not control OS migration before app startup. See [Sandbox](Sandbox.md).
Pass a normally built signed app path to `Scripts/verify-sandbox.swift` to check
actual signed entitlements; the source-only CI check cannot prove signing or runtime access.
No signing material belongs in Git.

Before a release, complete [TestFlight preparation](TestFlight.md), run the signed
hosted suite, and manually verify the system integrations. Build output is captured
in full with `tee` and `pipefail`, so a failed compiler cannot turn into a successful
step. On failure, CI retains `build.log` and the build `.xcresult` in a configuration-
and attempt-specific diagnostics artifact for seven days. It publishes neither app
bundles nor test data. Inspect the first actool error there, not just xcodebuild's
final failed-command summary. The job also logs host OS, Xcode version, and commit.
