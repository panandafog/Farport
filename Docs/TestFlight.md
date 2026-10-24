# TestFlight Preparation

Repository, unsigned CI builds, and a temporary app icon are initial preparation,
not a completed distribution pipeline. Do not upload the unsigned CI product.

## Remaining Release Gates

- Verify the signed archive's sandbox entitlements with
  `xcrun swift Scripts/verify-sandbox.swift /path/to/Farport.app` and check its
  signature with `codesign --verify --deep --strict /path/to/Farport.app`.
  Main app and extension now enable App Sandbox. Run the clean-install/upgrade
  checks in [Sandbox](Sandbox.md); source entitlements alone do not verify runtime access.
- Create/verify the App Store Connect app record for `com.panandafog.harbor` and
  distribution signing/profiles for both the app and `com.panandafog.harbor.finder`.
  Preserve existing shared App Group/Keychain identifiers to retain data access.
- Deploy the CloudKit schema to production and verify opt-in profile sync through
  the distribution build. Development CloudKit success is not a production check.
- Replace `AppIcon.icon` (currently copied unchanged from MediaPlayer/Trackfold)
  with Farport artwork, then validate the compiled icon in the archive.
- Review privacy disclosures, required-reason API/privacy manifests (including
  dependencies), support/privacy URLs, beta review information, and encryption
  export compliance. SSH uses encryption; do not assume an exemption without review.
- Increment the build number for every upload, keeping app and extension versions
  aligned. Archive the **Farport** scheme in **Release**, not **FarportLocal**.
- Validate the distribution archive in Organizer, including embedded-extension
  signing, production capabilities, and absence of debug/test-only entitlements.
- Run the signed hosted tests and exercise Local Network approval, unknown/changed
  server keys, ProxyJump, Keychain persistence, tmux recovery, Finder read/write,
  and iCloud on a clean test installation before inviting testers.

No App Store Connect credentials, certificates, private keys, provisioning profiles,
real host libraries, or terminal transcripts may be committed. Automated signing
and upload can be added separately with restricted CI secrets and an explicit
release trigger; ordinary pull requests must not have access to them.

## References

- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [iCloud provisioning and schema](iCloud.md)
- [Security and current limitations](Security.md)
