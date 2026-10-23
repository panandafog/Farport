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

Both run on `macos-15` with Xcode 26.3 explicitly selected. This runner includes that
toolchain, unlike its default Xcode 16.4, which cannot compile the Icon Composer asset.
Toolchain inventory: [GitHub runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
Review the selected Xcode path when updating the runner. Homebrew installs SwiftLint,
XcodeGen, and tmux; a new tool version can legitimately require a style/generation update.

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
hosted suite, and manually verify the system integrations. CI logs appear in the
Actions run; the workflow intentionally publishes neither app bundles nor test data.
