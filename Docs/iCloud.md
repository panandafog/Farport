# iCloud Host Profiles

## Scope

The sidebar's **iCloud Off / iCloud Hosts** button and **iCloud > Host Sync** open
the sync settings. Synchronization is off until explicitly enabled. Profiles merge
with the current Apple Account, not a public/shared database.

Synced fields are the host UUID, name, hostname, port, username, authentication
kind, terminal/file provider identifiers, initial directory, notes, tmux preference
and ordered ProxyJump host UUIDs. Never put secrets in names/notes.

Passwords, imported keys, passphrases, Keychain references, credential readiness,
server-key pins, workspace tabs/history and Finder locations stay on each device.
Newly imported profiles show a key badge and require local credentials. An empty
password requires explicit confirmation in the editor. Changing endpoint, username,
authentication or route invalidates readiness, but metadata-only changes retain it.
Trust every server/gateway independently on each device as before.

## Storage And Reconciliation

`HarborCloud` uses Apple's [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9)
in container `iCloud.com.panandafog.harbor`, private database, custom zone `HarborHosts`.
Each `HarborHost` record has a UUID record name and one Data field `profile` written
only through [encryptedValues](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues).
CloudKit encrypts that field on-device before upload; this is not a claim of
application-managed end-to-end encryption or a replacement for account security.

The atomic owner-only `hosts.icloud.json` beside `hosts.json` contains schema-1
sync metadata, the journal, change tokens and cached record system fields. It also
contains profile metadata in plaintext locally, never secret bundles. Keep it with
the host library; deleting only the journal loses the device's causal history.
Host-library schema 5 adds local credential readiness; schemas 1-4 migrate safely.

- First enabling fetches before publishing unversioned local profiles. Cloud
  versions take precedence for an existing UUID; differing local copies are retained
  in **Recovered Versions**. Unique local UUIDs are added, not erased.
- Subsequent local saves/deletes enter a durable per-host queue. Startup/foreground
  reconciliation captures a save even if the app stopped before journaling it.
  Offline records remain pending; CKSyncEngine schedules ordinary retries.
- Independent host edits merge. Same-host concurrent edits use a deterministic
  whole-profile Lamport revision (counter, then device UUID), not wall-clock time
  or field-by-field merging. A losing concurrent profile is retained locally.
- Tombstones are retained indefinitely. Deletion wins over stale/offline edits to
  that UUID, even with a higher counter. **Restore Copy** creates a new UUID, which
  does not automatically repair other profiles' gateway references.
- Up to 50 recovery copies are retained per device. They are not a cloud backup or
  a full version history. Dismissing a copy removes only that local recovery entry.
- Received changes affecting active sessions, the editor or connected Finder routes
  wait for **Apply Changes**. Confirmation disconnects affected transports/revokes
  Finder locations. Updated host tabs/buffers survive; deleted hosts close their
  tabs. An absent gateway remains an explicit broken route, never direct fallback.
- A stale cloud snapshot cannot overwrite a newly saved local library: its applied
  baseline must match the latest locally requested profile set.
- Disabling keeps local hosts, secrets, cloud records and the durable journal. It
  does not delete iCloud data. Re-enabling reconciles changes made while disabled.
- Account change/sign-out or zone reset pauses sync. Explicit re-enabling merges
  local profiles with the chosen account, with a fresh journal on account/reset
  change. This can publish local profiles previously used with another account;
  the enable confirmation makes that choice explicit. There is no per-account
  separate local library or remote erase command in this version.
- Unsupported/corrupt records or journal data stop sync without silently replacing
  the file. Permanent server rejections pause uploads; fix the cause and re-enable.
  Normal network failures retain the queue. **Sync Now** or foreground activation
  can retry an initial fetch that could not finish offline.

CloudKit pushes and foreground activation trigger refresh. Delivery is eventual,
not a live collaboration protocol, and no fixed sync latency is promised.
The Finder extension does not access CloudKit.

## Apple Developer Setup

1. Sign in to Xcode with the configured development Team. Ensure the account can
   manage identifiers, containers and profiles for that Team.
2. Enable iCloud/CloudKit with `iCloud.com.panandafog.harbor` and Push Notifications on the
   Harbor app identifier/target. Keep its existing App Group and Keychain group.
   The Finder extension retains only its existing capabilities.
3. Regenerate with `sh Scripts/xcodegen.sh generate` after changing `project.yml`. The Harbor
   scheme uses the cloud entitlement file; HarborLocal/Local deliberately does not.
4. Build with `-allowProvisioningUpdates`. A successful signature must include the
   container, CloudKit service and APNS environment as well as the original groups.
   An Apple ID signed into macOS iCloud is also needed for runtime sync.
5. Debug/development CloudKit creates the `HarborHost` encrypted `profile` schema
   when first uploading disposable test data. Before distributing a production
   signed app, deploy/verify that schema in CloudKit Console's production environment
   and configure production APNS/provisioning. The current MVP signing is development.

Use **HarborLocal**, configuration **Local**, when developing without cloud-capable
provisioning. The UI explicitly says iCloud is unavailable; this is not cloud success.

## Verification Boundaries

Portable tests exercise independent/concurrent edits, deletion precedence, stale
acknowledgments, first import, offline persistence and credential readiness. Hosted
UI-model tests exercise imported profiles, editor deferral, retained terminal output,
stale snapshots and missing gateways, using a fake service and disposable stores.
The hosted test schemes and Debug `--host-library` override bypass cloud creation.

A successful build or codec test does not prove real server synchronization.
Before release, use disposable profiles with two devices on the same Apple Account:
create/edit/delete offline and reconnect, restart both apps, resolve a concurrent
edit via Restore Copy, sign out/switch accounts and verify explicit re-enable.
Also verify background push delivery, quota failures and production schema access.
Never upload real/corporate profiles merely to perform a smoke test.

### Local Verification, 2026-10-21

The loopback package suite passed, including real SSH/SFTP, ProxyJump, tmux and
the new sync tests. All 47 hosted Xcode tests passed with no skips or runtime
warnings. SwiftLint reported zero violations and first-party code built without
compiler warnings. The signed Local build passed deep/strict signature validation;
the Finder extension retained sandbox/network/groups without test-only exceptions.

The initial container `iCloud.dev.harbor` was unavailable to the configured Team.
After switching the app to `com.panandafog.harbor`, the extension to
`com.panandafog.harbor.finder` and the container to `iCloud.com.panandafog.harbor`,
the cloud-capable Debug build succeeded. Signed entitlements and runtime Info.plist
agree on the new container and include CloudKit and development push access.
Existing App Group/Keychain identities are retained, not renamed with the bundle.
The new-ID hosted test run passed 44 tests with no runtime warnings; three live
SSH recovery tests skipped because the disposable Python fixture environment was
absent. SwiftLint remained at zero violations. No real library was uploaded.
No real CloudKit upload/download, two-device sync or cloud-settings UI smoke test
has been performed. The Local build explicitly disables iCloud.
