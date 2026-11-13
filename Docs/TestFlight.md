# TestFlight Preparation

Use the manual [release workflow](APP_STORE_RELEASE_AUTOMATION.md) for signed App Store
packages and draft review preparation. Unsigned ordinary CI products cannot be uploaded.
Real run results and remaining owner gates are recorded separately in that guide.

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
- Validate the compiled Icon Composer icon in the archive. The owner approved keeping
  the current artwork (originally MediaPlayer/Trackfold) for this upload on 2026-11-13.
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
and upload use restricted environment secrets and an explicit manual release trigger;
ordinary pull requests must not have access to them. See [compliance audit](ReleaseCompliance.md).

## References

- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [iCloud provisioning and schema](iCloud.md)
- [Security and current limitations](Security.md)
