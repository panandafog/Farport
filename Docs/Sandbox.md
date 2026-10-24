# App Sandbox

Debug, Release and Local enable App Sandbox for the main app. The Finder extension
was already sandboxed. Both can initiate outgoing connections; neither listens on
local ports. SSH, ProxyJump, SFTP and remote tmux run through the native transport,
not local ssh/tmux executables. Local Network privacy and host-key trust still apply.

The main app additionally permits user-selected read/write access. Key import,
upload and download use native open/save panels; scoped access covers the whole
operation. No local file URLs are retained for future launches, so persistent
security-scoped bookmarks are not needed yet. Download staging uses the system's
item-replacement directory on the destination volume, with cleanup on success,
failure and cancellation, preserving an existing destination until commit.

App IDs, App Group, Keychain service/access group and CloudKit container stay unchanged.
Finder configuration remains in the existing shared group; secrets and server pins
remain in the same Keychain. Sandbox does not require re-entering these secrets.

## Existing Data

`App/container-migration.plist` is bundled as a resource. When macOS first creates
the main app's sandbox container, it migrates the entire legacy
`~/Library/Application Support/Harbor` directory to the same relative location inside
the container. This includes hosts, workspace metadata, iCloud state and recovery
copies, not just host profiles. Application Support is located through FileManager;
there are no hard-coded container filesystem paths in app code.

The manifest is a first-container-creation mechanism, not a recurring import. It
will not re-import later edits from an old unsandboxed copy, and it does not merge
two libraries. Do not alternate unsandboxed and sandboxed builds once migrated.
If a container already existed before this manifest was installed, preserve both
directories and resolve the migration explicitly; do not delete a container or
overwrite its iCloud queue to force a retry. An automatic repair/import UI for that
unusual case is not implemented.

## Verification

```sh
xcrun swift Scripts/verify-sandbox.swift
xcrun swift Scripts/verify-sandbox.swift Build/Build/Products/Debug/Farport.app
codesign --verify --deep --strict Build/Build/Products/Debug/Farport.app
```

The first command is also in CI: it requires actual Boolean entitlements in both
main-app configurations and the extension, and checks the narrow migration manifest.
Passing an app path additionally checks the signed main app/extension and bundled
manifest, and rejects stale extensions or embedded test bundles. Run after a normal
build, not on a hosted-test-injected product. If Xcode retains old plugins after a
rename or test build, clean this project's build products and rebuild; do not remove
required extensions or relax the check. For a
Release archive, pass `Archive.xcarchive/Products/Applications/Farport.app`; verify
distribution signing separately in Organizer. Rebuild/archive after changing
entitlements: an existing archive does not receive these changes retroactively.

Before release, use a disposable macOS account to test a clean sandbox install and
an upgrade from a populated unsandboxed version. Verify local host/Keychain/pin and
workspace retention, iCloud pending-state retention without implicit publication,
SSH/ProxyJump, key import, multi-file upload, new-file download and existing-file
replacement/cancellation, and Finder read/write. Check files on an external volume
and a File Provider location too. Do not run migration tests against real user data.

Package integration tests cover transport and destination preservation, but are
not sandbox permission tests. Hosted tests may gain Xcode-injected permissions;
they cannot establish production sandbox behavior. Their isolation environment
flag does not prevent macOS migration before app startup. External Python/tmux
fixture executables are test tooling, not production sandbox capabilities.

## References

- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Container migration](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container)
- [User-selected file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Temporary replacement directories](https://developer.apple.com/documentation/foundation/filemanager/url(for:in:appropriatefor:create:))
