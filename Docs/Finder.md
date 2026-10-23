# Finder Integration

Harbor retains its existing Files UI. Optional Finder integration uses Apple's
`NSFileProviderReplicatedExtension`, not SSHFS, macFUSE, SMB, or a synchronous SFTP
mount. Locations can be **Read Only** or **Read & Write**. The existing Files UI
remains available independently.

## Workflow

Use the Finder connections menu in the host header, choose **Connect Folder to
Finder**, and confirm the remote folder. It defaults to the current Files folder
or the host's initial directory. Select access explicitly; the new-location form
defaults to Read & Write, while existing/legacy saved locations remain read-only.
The same host/root with different access gets a separate domain, never an implicit
permission upgrade. Harbor canonicalizes and checks that directory
through the complete saved ProxyJump route before registering a separate domain.
macOS may require enabling Harbor Files under File Provider extensions in System
Settings. The domain appears in Finder; opening a file downloads it on demand.

Each domain has Open, Refresh, and Disconnect actions in Harbor. Domains survive
quitting Harbor; macOS can run the extension independently. This is an explicit
opt-in to background file access, unlike restored terminal tabs. Only previously
connected domains are eligible. Files downloaded by macOS may remain cached and
readable offline; uncached files need the network. Errors are reported through
File Provider, not as an empty or successfully connected server.

Disconnect revokes the connection configuration and removes the domain using
`preserveDownloadedUserData`. macOS may retain downloaded files in a relocated
folder. This is not a secure erase. If system removal fails, the configuration
still remains revoked and the error is displayed. Editing a host or any gateway
revokes its affected Finder domains; connect again explicitly with the new route.

## Scope And Consistency

- Only directories explicitly visited are indexed; no recursive indexing of a
  server or large source tree, automatic content download, or remote helper files.
- The live extension signals changes every 30 seconds. Working-set enumeration
  refreshes up to 16 known folders per batch in rotation. The system controls
  extension execution and scheduling; this is not a guaranteed refresh deadline.
- Refresh signals the working set and root; subsequent batches refresh other
  visited folders. A folder opened directly is refreshed on enumeration.
- Persistent item IDs survive our own rename/move, including indexed descendants,
  and application/extension restarts. Legacy path IDs remain valid. An external
  rename is represented as delete/create because SFTP has no portable stable IDs.
- A private per-domain index stores metadata, epoch/revision sync anchors, and a
  bounded change journal. Expired anchors request a system rescan. Corrupt/newer
  indexes are reported, not silently overwritten.
- Polling versions use SFTP size and modification time. Same-size changes retaining
  the same timestamp may be missed during enumeration. Downloaded/created files
  also store SHA256 for conflict checks before replacement. There is no server
  change feed or revision API.
- Downloads check metadata before and after transfer and discard a detected
  conflicting version. There is no atomic snapshot guarantee against remote writers.
- Symlinks are omitted. Canonical paths are checked against the selected subtree.
  This is a client boundary, not a server chroot; SFTP has no portable no-follow
  open primitive to eliminate malicious rename/symlink races entirely.
- Names that collide under Swift's Unicode normalization are rejected rather
  than crashing or merging distinct remote entries. The local APFS volume's name
  and case-sensitivity constraints still apply; this is not a Linux filesystem.
- Read-only domains expose no mutation capabilities and reject all write callbacks.
  Local copies made outside the location remain ordinary editable local files.

## Writes And Conflicts

Writable domains support creating files and directories, per-item folder copying,
renaming/reparenting, saving existing files, and permanently deleting files or
empty directories. There is no remote Trash. Nonempty-directory deletion is rejected,
including a recursive deletion request; delete its contents explicitly first.
Symlinks/aliases and simultaneous rename/move plus content replacement are not
supported. Unsupported metadata fields remain pending, never falsely acknowledged;
full Finder tags, extended attributes, and permissions synchronization are not implemented.
Ordinary files, including `.DS_Store`/AppleDouble files if macOS requests them, are
not name-filtered. This is not a metadata-free mount.

Creation uploads to a sibling staging file and uses no-overwrite rename. Saving an
existing file uses `RemoteFileReplacingSession`; the SFTP adapter requires version 1
of `posix-rename@openssh.com`. It checks the original size/mtime and SHA256 before
staging and again immediately before atomically renaming the completed replacement.
Servers without this capability return a synchronization error, leaving the original
untouched. Never delete the original as a fallback. POSIX mode bits are retained;
ownership, ACLs, hardlinks, and extended attributes are not fully preserved by replacement.

If a materialized file changed remotely, the edit is uploaded as a deterministic
`name (Harbor conflict <digest>).ext` sibling and the server original is fetched back
into the edited item. Repeating the same request does not create extra copies.
Unknown/legacy baselines also take this conservative conflict-copy path. This is not
transactional multi-user storage: SFTP offers no atomic compare-and-swap, so a remote
writer can still race between the final fingerprint check and rename. Use version
control/backups for important data; do not treat these checks as a no-loss guarantee.

The schema-2 catalog persists mutation intent before sending a write, stable IDs,
creation receipts, and completed change records. On restart/lost acknowledgment,
recovery only observes the remote result; it never resumes a destructive write
while browsing. Matching committed results are adopted and explicit retries can
continue. Operations are serialized per domain, with one upload pipeline configured.
This is acknowledgment recovery, not resumable chunk upload or a second offline queue.
The system owns local pending contents; failed uploads are not acknowledged as
successful. macOS controls retries/error badges, and disconnecting with pending
edits is not a guarantee those edits reached the server.

## Architecture And Storage

`HarborCore` owns protocol-neutral paths, route snapshots, the reader/writer,
metadata catalog/journal, and bounded/cancellable requests using `RemoteFileSession`.
Atomic replacement is an additional explicit capability, not an SSH assumption in
File Provider callbacks.
`HarborFinder` adapts these values/errors to Apple's framework. The extension
contains lifecycle/enumeration callbacks. The app manages domains and opens the
system-provided user-visible URL; no path under CloudStorage is hardcoded.

`HARBOR_APP_GROUP` (`group.dev.harbor.shared.<Team ID>`) stores `Finder/Connections/<domain UUID>.json` and
`Finder/Indexes/<domain UUID>/catalog.json`. Each explicitly selected target includes
only its route's profiles and independent Keychain references, not the whole host
library. Schema 2 contains no password/private-key/passphrase fields. The main app
migrates old snapshots only after verifying Keychain writes; the extension never
migrates/recreates configs during a read. The original host library is not
moved, and a Debug `--host-library` path is never sent into the sandboxed extension.
No security-scoped bookmark to the original credentials file is required.

Before each remote operation the extension reloads and validates the snapshot.
Each request gets an independent SSH route and closes the entire chain on completion,
cancellation, or a 30-second inactivity deadline. Transfer and remote fingerprint
verification progress renew that deadline, so actively transferring files are not
cut off merely because the total operation exceeds 30 seconds.
SSH handshakes retain their own
bounded connector deadlines. No shell, tmux, copied keys, SSH config, agent forwarding,
or local listener is used. Every endpoint must match its shared Keychain host-key
pin. Unknown/changed keys fail closed without background prompts; review the endpoint
in Harbor and retry. See [Security](Security.md) for signing, migration, and trust limits.

File Provider has an iOS/iPadOS counterpart; the portable reader and transport can
be reused. This macOS extension is not yet an iOS target or verified iOS feature.
Future protocols should implement `RemoteFileSession`, then add explicit provider
selection in the factory rather than putting protocol logic in Finder callbacks.

## Build And Verification

Regenerate `Harbor.xcodeproj` using XcodeGen after editing `project.yml`. The Team
selected in Xcode is recorded in `project.yml` so regeneration preserves it. Both
targets need explicit App IDs and profiles authorizing the shared App Group.
`REGISTER_APP_GROUPS=YES` is required on macOS so automatic provisioning includes
the `group.` entitlement rather than silently choosing a wildcard profile without it.
The extension has App Sandbox and outbound-network entitlements; the main app
retains its existing unsandboxed behavior. No third-party driver is required.

```sh
sh Scripts/lint.sh
xcodegen generate
xcodebuild -quiet -project Harbor.xcodeproj -scheme Harbor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath Build -allowProvisioningUpdates build
/private/tmp/harbor-test-env/bin/python Scripts/ssh_fixture.py --tmux --run-tests
```

Unit tests cover identifier validation, scope checks, read-only capabilities,
binary download, version races, cancellation, private configurations, durable
change anchors/deletions, journal expiry, and error classification. A loopback
integration test downloads through ProxyJump and verifies gateway shells remain
unused. Verify real Finder enumeration/materialization using only the disposable
fixture. Never activate a user's corporate server for a UI test.

Write tests additionally cover real binary atomic replacement through ProxyJump,
stale fingerprint rejection, upload cancellation/staging cleanup, conflicts with
unchanged size/time, durable retry receipts, renamed-descendant identities across
restart, nonempty-directory protection, and File Provider mutation callbacks.
Richer sync diagnostics, recursive operations, and transfer
resumption remain future work.

## Read-Only UI Verification 2026-10-20

- 55 package tests and 36 Xcode tests passed, with no skipped tests. SwiftLint
  reported zero violations. The Xcode run reported no runtime warnings.
- Signed app/extension profiles both authorize the Team-scoped App Group. Real
  Finder activation required its standard Enable button on this Mac.
- A disposable loopback server appeared in Finder through ProxyJump. Opening a
  file in TextEdit downloaded the correct content and showed a locked document.
- Remote creation and content updates appeared in Finder. Reopening the changed
  file fetched the updated contents while the main Harbor process was closed.
- Relaunching Harbor restored the connection actions. Disconnect removed the
  active Finder location and preserved the downloaded file in a local folder.
- Fixture and test app processes were stopped; the user's separate Xcode-launched
  Harbor was left running. No corporate server was contacted.

Manual verification used macOS 27.0.1. The declared macOS 15 minimum has not been
separately exercised on a macOS 15 machine. Dependency manifest warnings (for
example BigInt's old watchOS declaration) are distinct from first-party lint.

## Write Verification 2026-10-20

- 65 package tests passed against the disposable loopback/tmux/ProxyJump fixture;
  37 Xcode tests passed with no skips or runtime warnings. SwiftLint reported zero
  violations. No first-party compiler warnings remain; upstream BigInt/Citadel
  diagnostics are separate.
- Tests verify binary atomic replacement, stale hashes, cancellation cleanup,
  conflict-copy deduplication, stable rename identities, restart/lost acknowledgments,
  explicit server rejection, read-only legacy migration, and idempotent deletion.
- Writable File Provider callbacks were tested with an injected disposable transport;
  the signed app and extension built successfully. Actual Finder/editor saves were
  NOT manually verified: the Mac was locked and the user requested continuing
  without interface verification. The read-only observations above are not write QA.
- The standalone test app/server were stopped. The user's separate Xcode-launched
  Harbor and real servers/libraries were left untouched; no new test domain was activated.
