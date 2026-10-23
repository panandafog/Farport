# Credentials And Server Trust

## Credential Storage

The signed application uses `ProtectedHostRepository`, not the legacy plaintext
`JSONHostRepository` codec. Host-library schema 5 stores profiles, device-local
credential readiness and opaque
credential references. Passwords, imported OpenSSH private-key text, and passphrases
are encoded together in a generic-password Keychain item, resolved into memory
only when loading a saved profile. Notes and other profile metadata in the local
JSON are not encrypted. Opt-in CloudKit records use `encryptedValues`.

`HarborSecurity` implements the protocol-neutral `SecretStore` using Apple's Data
Protection Keychain. App and extension share the explicit entitlement
`$(AppIdentifierPrefix)dev.harbor.shared`, configured as `HARBOR_KEYCHAIN_GROUP`.
The service is `dev.harbor.secrets`; queries always specify service, account,
access group, and Data Protection Keychain. There is no legacy-keychain or JSON
fallback when the shared group, signing, or Keychain is unavailable.

Items are non-synchronizable and use `AfterFirstUnlockThisDeviceOnly` accessibility.
This permits explicitly enabled Finder background access after the first unlock
following boot; it is not a per-connection Touch ID prompt or an iCloud secret sync.
Queries disallow authentication UI. In-memory secrets still exist while profiles
and active transports are loaded; Keychain does not eliminate that requirement.
The current app resolves all saved credentials when loading its library, not lazily
only when a connection starts.

See Apple's [Keychain sharing guide](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps),
[Data Protection Keychain selector](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain),
and [accessibility definition](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly).

## Migration And Failure Handling

The application reads legacy host-library schemas 1/2/3/4 and migrates to schema 5
on load. Each new secret gets an immutable UUID reference and is read back before
the JSON document is atomically replaced. Editing credentials rotates the reference;
profile-only changes reuse it. Missing/inaccessible Keychain items are errors,
never empty passwords. Corrupt or newer documents are not silently replaced.

Finder connection schema 2 contains only its selected route's profiles and separate
credential references, retaining the domain UUID/root/access mode. Copies have
independent ownership: deleting a main-library host cannot delete a live snapshot's
credentials. Host editing/deletion still explicitly revokes affected Finder locations.
Only the main app migrates legacy Finder snapshots; the extension asks the user to
open Harbor instead of rewriting a potentially revoked configuration during a read.

If a migration fails before the metadata commit, the original plaintext file is
kept. A failed write or interrupted migration can leave unreferenced Keychain items;
they are not globally garbage-collected. After a successful commit, obsolete items
owned by that document are removed best-effort. Cleanup failure does not invalidate
new references. Deleting/revoking a document removes the metadata first, then retires
its own credentials; it never performs a broad service/group delete.

Manually copying reference-only JSON does not duplicate the Keychain items or make
a portable credential backup. Removing a profile can invalidate such a copied
reference. iCloud sync transfers profiles only, not credential references or secrets.
Imported profiles store an intentionally empty local bundle marked unconfigured,
not a missing-Keychain recovery fallback. They cannot authenticate until explicitly
configured on this device (including an explicit opt-in to an empty password).
Changes to hostname, port, username, authentication or jump route invalidate readiness
of an existing profile. No server pins or Finder locations are synced.
See [iCloud](iCloud.md) for account changes, conflicts and remaining verification.

This is not secure erasure of the old plaintext: APFS snapshots, backups, copied
libraries, crash logs, and older app builds are outside this migration. Quit older
Harbor builds before using the new version; old code cannot read the new schemas
and could recreate plaintext if still allowed to save legacy data.

## Host-Key Policy

Every SSH endpoint is verified independently before authentication, including all
ProxyJump gateways and the final destination. Identity is the literal hostname
(case-insensitive) plus port, not username or saved-host UUID. There is no local DNS
lookup for private gateway-resolved names. Aliases and trailing-dot spellings remain
separate identities; the same private hostname/port behind unrelated gateways shares
one pin and may intentionally fail closed until profiles are disambiguated.

`ServerKeyValidator` hashes the SSH wire-format public-key blob with SHA256 and
displays the standard unpadded `SHA256:` fingerprint. Pins are themselves stored in
the shared Keychain under endpoint-derived accounts. They are not credentials and
may be shown/copied in the interface. Keychain I/O runs off the SSH event loop.

- An unknown key closes the attempted connection and shows its endpoint, algorithm,
  and fingerprint in the main app. Verify it independently, then explicitly choose
  **Trust & Connect** for a waiting terminal/Files attempt. After the sheet dismisses,
  that explicit action starts one fresh connection which verifies the stored pin.
  **Trust Server** without a pending attempt only stores the pin. No socket waits
  open for a UI decision and there is no accept-on-first-use or trust-once bypass.
  Pending callbacks are generation-scoped: Cancel, host editing/deletion and tab
  closure invalidate them. Trusting a key never starts unrelated sessions.
- A matching key is accepted for terminal, Files, Finder, reconnect, and new route
  connections. Concurrent first-use decisions cannot overwrite a different pin.
- A changed key closes the connection, shows old and new fingerprints, and does
  not auto-retry. It cannot be accepted over the existing pin. After independent
  verification, explicitly forget the old key, reconnect, and confirm the new one.
- **Security > Server Keys** shows pins for saved endpoints and supports confirmed
  forgetting. Forgetting does not terminate already established sessions; it affects
  later handshakes/rekey checks. Conditional deletion uses the Keychain item's
  persistent identity so it cannot delete a newly inserted replacement pin.
- Finder never displays trust prompts or accepts new keys in the background. It
  reports the blocked endpoint/fingerprint as an authentication/sync error. Open
  that host in Harbor to review and approve the endpoint, then retry Finder access.

All trust/store/configuration failures are permanent for automatic terminal recovery;
no fallback to direct SSH, a fresh shell, or unchecked keys is allowed. The transport's
default without an injected verifier rejects unknown keys, including package clients.

This is explicit TOFU/pinning, not independent server identity proof. There is no
system `known_hosts` import, SSH CA/certificate trust policy, DNS SSHFP validation,
automatic key rotation, multiple-algorithm pin set, or cryptographic/security audit.
Existing library algorithm negotiation is unchanged. First-use fingerprints must
still be verified through a trusted channel.

## Local Network Privacy

macOS Local Network approval is separate from SSH trust and sandbox entitlements.
The main app declares `NSLocalNetworkUsageDescription` for LAN SSH/SFTP and Finder.
Changing the bundle ID changes app identity; do not silently reset/modify system
privacy settings to recover old access. The user must approve network access.
See Apple's [local network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

`NIOConnectionError error 1` is a Foundation wrapper, not POSIX errno 1. Diagnostics
retain each attempt's actual DNS/TCP failure. EACCES/EPERM do not auto-retry.
EHOSTUNREACH alone is ambiguous. After that error on an initial direct connection,
a cancellable TCP-only Network.framework check runs for at most one second. Only
`currentPath.unsatisfiedReason == .localNetworkDenied` confirms a privacy denial;
unknown outcomes preserve the original error. The check sends no SSH credentials,
closes on completion/cancel, and never resolves/probes destinations behind ProxyJump.
No host-key bypass, privacy reset, firewall change or automatic permission grant is used.
The app presents a confirmed privacy requirement as a separate Local Network step,
with Open Settings and Continue, not a red transport failure. First-use server-key
confirmation has its own neutral Verify Server Identity step. Changed keys remain
blocking red warnings; they cannot use Trust & Connect to replace an existing pin.

## Verification

Use disposable loopback servers and out-of-band exported public keys. Never approve
a real/corporate endpoint just for a UI test. Package tests cover migration failure,
missing items, reference rotation/isolation, first-use/mismatch/retry policies, and
strict gateway/destination validation. Network fixtures export their generated host
public keys and tests pin those exact bytes; tests do not use accept-any validators.

Hosted Xcode tests use unique Keychain services/accounts and remove their own items.
They test real shared-group read/insert/duplicate handling, conditional removal,
pin persistence, and rejection of an unentitled group. The scheme sets
`HARBOR_ISOLATED_TESTS=1` so launching the host app does not migrate the real library.
The test target has its own plist and must never advertise itself as a File Provider.

## Connection Flow Verified 2026-10-21

- 100 package tests passed with loopback SSH/SFTP/ProxyJump/tmux fixtures. All 54
  hosted Xcode tests passed without skips or runtime warnings. SwiftLint remained
  at zero violations; a normal signed build passed deep/strict verification and
  the extension had no test-only filesystem/Mach-lookup exceptions.
- The isolated UI showed Verify Server Identity with the independently exported
  fixture fingerprint. Trust & Connect entered a live SSH terminal without another
  Connect click. ProxyJump showed gateway and destination prompts in sequence, then
  connected. SFTP through the same route listed the fixture directory successfully.
- Permission guidance and cancellation/stale-continuation handling were exercised
  with controlled model tests; existing system Local Network approvals were not
  reset just to show another OS alert. Changed-key rejection remained covered.
- With the user's approval, all three temporary profiles and their Keychain
  credentials/pins were removed using the isolated app. Its process and fixture
  were stopped. Real hosts, credentials and trusted server keys were not modified.

## Security Baseline Verified 2026-10-21 (Before iCloud)

- 74 package tests passed with the loopback/tmux/ProxyJump fixtures. 42 hosted Xcode
  tests passed without skips or runtime warnings. SwiftLint reports zero violations;
  no first-party compiler warnings remain. Upstream manifest warnings are separate.
- Real Data Protection Keychain tests cover shared-group queries, immutable inserts,
  stale/conditional deletion, durable pins, and rejection of an unentitled group.
- In the isolated app, a legacy library migrated to schema 4 without credentials in
  JSON. The unknown-key prompt matched `ssh-keygen -lf -E sha256`; explicit approval
  enabled SSH, and trust/credentials survived restarting the app. The Server Keys
  panel displayed the pin and confirmed forgetting it. The test host/domain/pin
  were removed through Harbor; real SSH sessions were left running.
- Finder registration was exercised and a test-plist configuration defect was fixed.
  End-to-end Finder/editor saving was NOT verified: the user requested finishing
  without that check. No real/corporate server was used for verification.
- A normal signed build was produced after tests; signature verification passed and
  the extension's temporary test-only filesystem/Mach-lookup entitlements were absent.
