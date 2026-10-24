# Farport Contributor Guide

## Project

Farport is a native macOS SSH/SFTP client MVP, inspired by the basic host-library,
terminal, and file-browser workflow of Termius. Optional read-only/read-write Finder access
uses Apple's replicated File Provider, not a synchronous mounted SFTP volume.
Minimum OS: macOS 15. Shared-package deployment declarations also include iOS 17;
iOS/iPadOS apps are planned, not implemented or verified.

Project, targets, schemes, package and module names use Farport. Keep
`com.panandafog.harbor` / `.finder`, CloudKit container/zone/record names, App Group,
Keychain services/keys, Application Support/Harbor, tmux `harbor-` names and deterministic
`Harbor conflict` filenames unchanged. Preserve the legacy Harbor* Info.plist keys and
HARBOR_* build/environment variables. The app product and module are Farport; the
repository directory and Xcode project are Farport and Farport.xcodeproj.

- `App/`: SwiftUI interface, AppKit file panels, SwiftTerm terminal, UI models.
- `Sources/FarportCore/`: portable models and storage/connection/session contracts.
- `Sources/FarportSSH/`: Citadel/SwiftNIO SSH and SFTP adapter.
- `Sources/FarportSecurity/`: shared Data Protection Keychain adapter.
- `Sources/FarportCloud/`: CloudKit private-database sync and durable offline queue.
- `Sources/FarportFinder/`: macOS File Provider items, error mapping, shared storage.
- `FinderExtension/`: sandboxed replicated File Provider and enumerators.
- `Tests/`: Swift Package model/storage and local-server integration tests.
- `AppTests/`: Xcode tests for the macOS terminal model and retained output.
- `Vendor/Citadel/`: pinned upstream code with narrowly scoped patches; document
  every additional patch in `Vendor/Citadel/UPSTREAM.md`.
- `project.yml`: XcodeGen source of truth; regenerate the included Xcode project
  after project-configuration changes. Do not hand-edit generated project files.
- `AppIcon.icon`: temporary Icon Composer artwork copied from MediaPlayer/Trackfold;
  replace before distribution. Requires Xcode 26.3+; keep it as one resource bundle.
- `App/Assets.xcassets/AccentColor.colorset`: shared UI accent, with light/dark
  variants. Use `Color.accentColor`; keep semantic status and terminal ANSI colors separate.

## Product Direction

Keep the first version focused on saved hosts, interactive SSH, and basic SFTP.
Optional iCloud profile synchronization is implemented. Future work includes additional
file protocols and iOS/iPadOS clients. Preserve the existing SFTP browser alongside
Finder integration. Basic File Provider writes are implemented; broader metadata
sync, resumable transfers, and recursive deletion remain future work.

Preserve the boundaries between UI, storage, and transport. Core must not import
AppKit/UIKit or depend on SSH-specific types. Keep terminal and file capabilities
separate. Additional protocols should use provider/session adapters and explicit
capabilities rather than SSH assumptions in file-browser views.

The application uses ProtectedHostRepository: profiles/references in schema-5 JSON,
password/private-key/passphrase bundles in the shared Keychain. JSONHostRepository
is a legacy import/test-fixture codec, never the application's save path. Migrate
only after inserting and verifying secrets; never default to plaintext or empty
credentials on an error. Keep immutable secret references and per-document ownership.
No real credentials, host libraries, transcripts, or private keys in the repository.
See Docs/Security.md for failure handling, trust policy, and residual limitations.

Session recovery design is in `Docs/SessionRecovery.md`. Optional tmux mode is
implemented per terminal tab, with a UUID-derived server session name and PTY exec attach.
Disconnect, app exit, host editing, and deletion detach without killing remote
sessions. Standard SSH remains the default for existing and new hosts. Missing
tmux is an explicit error; do not silently fall back to a fresh shell. The host
library migrates schemas 1/2/3/4 to schema 5, preserving routing and session mode.
Terminal heartbeat and bounded automatic tmux reconnect are implemented. Shared
`ConnectionRecoveryPolicy` defaults to a 15-second heartbeat, 10-second response
timeout, and retry delays of 1/2/4/8/16/30 seconds. Only typed transient transport
failures retry; clean terminal exit, Detach/Cancel, authentication, configuration,
and host-key failures stop recovery. The retry budget resets after a successful
heartbeat, not merely on opening a new connection. Standard SSH never starts a
replacement shell automatically. Local transcript persistence is future work.
Never replay commands or install server software implicitly.

iCloud sync is opt-in, using CKSyncEngine and encrypted per-host records in the
private CloudKit database. Keep CloudKit out of Core. Sync HostProfile only, never
SavedHost, Keychain references/secrets, server pins, Finder locations, or workspaces.
Imported hosts require explicit local credential setup, even for an empty password.
Endpoint/authentication/route changes invalidate local credential readiness. Keep
whole-profile deterministic revisions, durable tombstones, pending edits and bounded
recovery copies. Do not compact tombstones or overwrite incompatible sync state.
Account changes pause sync and require explicit re-enabling. Never automatically
publish a real user's library during tests. Initial fetch precedes publication.
Active affected sessions/Finder domains defer remote application; confirmation may
disconnect them, retaining updated-host terminal buffers. Preserve baseline guards
against stale snapshots racing a local save. See `Docs/iCloud.md` for provisioning,
schema deployment, conflict rules, and test limitations.

Terminal appearance follows the native view's effective system appearance via
`SystemTerminalView`. Use resolved AppKit text/background colors for defaults and
separate readable ANSI-16 palettes for light/dark mode. The SwiftUI padding must
use the same system text background. Repaint the existing terminal; never recreate
it, replay output, alter cell attributes, clear selection/history, or send input
when changing theme. Do not reinstall palettes on unchanged appearance callbacks.
Indexed colors 16-255 and true-color values keep their standard meaning. Explicit
application colors/background combinations are not automatically inverted/recolored.
Theme tests cover contrast, SGR styles, selection, retained output, hidden cursor,
palette queries, live window appearance changes, and offscreen render attachments.

Native ProxyJump uses Citadel `jump(to:)` and direct-tcpip, shared by SSH and SFTP.
`HostProfile.jumpHostIDs` stores ordered saved-host references, not copied secrets
or shell commands. `ConnectionRoute` expands nested routes, rejects missing or
duplicate nodes/cycles, and bounds the route to eight endpoints including target.
The UI selects one saved jump host per profile; that host may have its own route.
Corporate DNS resolution happens at the preceding gateway, never by resolving the
final hostname locally first. Do not launch shells/tmux on gateways, forward the
agent, copy keys, expose local listening ports, or silently fall back to direct SSH.
Each terminal/file session owns its independent full chain and closes it in reverse
order. Forwarding/authentication have bounded deadlines and cancellation cleanup.
Forwarding rejection is a permanent actionable error (permissions/reachability);
transport/timeouts remain retryable. Stage context must preserve typed retry policy.
An established tmux reconnect rebuilds the complete route before attaching the same
tab UUID. Saving a host refreshes it and all transitive dependents, disconnecting
their transports while retaining tabs and in-memory terminal buffers. Deletion of
a referenced jump host is blocked. `~/.ssh/config`/agent import and generic local
port-forwarding UI are not implemented. Every endpoint must pass the shared explicit
host-key verifier; no accept-any or direct fallback in first-party production code.

Multiple terminal tabs per host and local workspace restoration are implemented.
`WorkspaceRepository` in Core stores versioned metadata separately from credentials.
`hosts.workspace.json` sits beside `hosts.json` (including Debug library overrides).
Persist tab UUIDs/names/order, selected host/tab, and Terminal/Files mode immediately
on changes, and checkpoint on termination. Restore disconnected without network
activity. Never persist live connection/retry intent. The first default tab uses
the host UUID to preserve pre-tabs tmux sessions; subsequent tabs get independent
UUIDs. Rename must not change identity. Switching hosts/tabs/views retains native
terminal instances and their buffers; closing a tab detaches only its connection.
Closed tabs are removed from the workspace, without killing remote tmux sessions.
Corrupt/newer workspace files must not be silently replaced. Local scrollback is
not written to disk; remote screen/history recovery still depends on surviving tmux.

Finder connections are explicit opt-ins, independent of terminal/Files connections.
Use `FinderLocation` route snapshots containing only the selected target and its
gateways. The app and extension share `HARBOR_APP_GROUP` (a Team-scoped `group.` ID), with profiles and
real signing; never fall back to an unprotected globally shared directory. Both targets
also require HARBOR_KEYCHAIN_GROUP in their entitlements/profiles and Info.plists.
Finder schema 2 stores profiles and independent Keychain references, not secrets.
Only the main app migrates legacy Finder snapshots; extension reads must never
rewrite/recreate revoked configs. Never log secrets. Host/route editing
revokes affected Finder configurations. Each remote request reloads its configuration,
opens its own complete SSH route, and closes it on success, timeout, or cancellation.
No shell, agent forwarding, server installation, or remote helper files are needed.

Finder access is explicit per domain: existing/legacy connections default to read-only,
and writable connections require a new opt-in. Enforce read-only in both capabilities
and mutation callbacks/core operations. Acknowledge writes only after remote success
and persisted journal updates. Symlinks are omitted,
canonical remote paths must match the selected root and descendants. These checks
are not a server chroot and cannot eliminate SFTP symlink races against a hostile
server. Persist a per-domain metadata index and bounded change journal; poll only
visited folders in rotating batches, never recursively walk a source tree or prefetch
file contents. Polling versions use SFTP size/mtime and can miss same-size/same-time
external changes; materialized files also store SHA256 for write conflict checks.
Persist stable IDs across our own rename/move, including indexed descendants. The
schema-2 journal records pending intent and creation receipts before acknowledging
mutations. Retry recovery observes remote state, never starts destructive writes
during browsing. Serialize operations per domain across actor suspension points.
Atomic replacement must use an explicit transport capability; SFTP requires the
OpenSSH POSIX rename extension. Never fall back to remove-original-then-rename.
Check the original fingerprint before staging and before commit; preserve conflicting
local edits in a deterministic remote sibling. No SFTP atomic compare-and-swap exists,
so document the remaining check/commit race and metadata preservation limits.
Only delete files/empty directories; no remote Trash, recursive delete, symlinks,
or combined rename and content replacement in this stage. Unsupported fields must
remain pending or fail, never be falsely acknowledged. Offline errors must never become
"no such item" errors, which would tell the system to remove cached files. System
cache/download behavior after restart belongs to macOS, not terminal restoration.
Disconnect preserves downloaded data, never remove-all. See `Docs/Finder.md`.

## Style Checks

Use SwiftLint (validated with 0.65.1), installed using `brew install swiftlint`.
`.swiftlint.yml` uses the upstream default rule set, with focused opt-in rules for
sorted imports, private SwiftUI state, avoiding force unwraps, and empty checks.
There is no separate official SwiftUI preset; this is the standard ruleset with
small documented additions, not a claim of an Apple-endorsed configuration.

```sh
sh Scripts/lint.sh
swiftlint lint --fix --no-cache --config .swiftlint.yml
sh Scripts/lint.sh
```

The script uses `--strict`, so warnings fail the check. Xcode runs the same script
before building; missing SwiftLint is an error, not a silently skipped check.
Keep first-party Swift code warning-free. Fix code instead of raising thresholds,
adding a baseline, or broadly disabling rules. Exclude generated build output,
downloaded dependencies, and vendored upstream code from style checks. Do not
reformat third-party sources; compiler diagnostics from dependencies are distinct
from first-party lint results. Avoid suppressing compiler warnings globally.

Use four spaces and the default 120-character line limit. Prefer small named
helpers when they reduce real branching or overly dense view expressions.

## Build And Test

Run commands from the repository root. Requires Xcode and SwiftLint. Regenerate
only through `sh Scripts/xcodegen.sh generate`: it installs the checksum-pinned
official XcodeGen 2.44.1 binary/presets in ignored `Build/Tools`, shared by local
development and CI. Do not use an arbitrary Homebrew XcodeGen version or remove
CI's generated-file diff check to accommodate toolchain drift. Updating the pin
requires reviewing/regenerating the project and updating its official SHA-256.

```sh
sh Scripts/lint.sh
sh Scripts/xcodegen.sh generate
xcodebuild -quiet -project Farport.xcodeproj -scheme Farport \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath Build build
xcodebuild -quiet -project Farport.xcodeproj -scheme Farport \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath Build test
swift test
```

The Farport scheme requires a CloudKit-capable profile for `iCloud.com.panandafog.harbor` and
Push Notifications, in addition to the shared App Group/Keychain. `FarportLocal`
uses configuration `Local` with those shared security entitlements but no iCloud
or push entitlement; its cloud toggle is unavailable. It is for offline development,
not a fallback that pretends sync is working. Both hosted test schemes isolate the
library and do not construct CKContainer. After hosted tests, run a normal build
and verify the extension has no test-only filesystem/Mach-lookup exceptions.

Application identifiers are `com.panandafog.harbor` and the embedded extension's
`com.panandafog.harbor.finder`. Keep them in `project.yml`, not only Xcode's editor.
The older `group.dev.harbor.shared.<Team ID>`, Keychain group and secret service
names intentionally remain unchanged to preserve existing data access. Do not
rename these storage identities as part of a bundle-ID cleanup.

Keep NSLocalNetworkUsageDescription in the main app's generated Info.plist source
(`project.yml`), not just a built product or the Finder extension. Local Network
privacy is independent of sandbox network entitlements and host-key trust. Do not
reset or bypass privacy controls, auto-grant permissions, or infer a denial from
NIOConnectionError's generic NSError code. Preserve its underlying DNS/POSIX causes;
explicit EACCES/EPERM failures require user action rather than automatic reconnect.
For an initial direct EHOSTUNREACH only, a bounded/cancellable Network.framework
TCP probe may check `currentPath.unsatisfiedReason == .localNetworkDenied`. That
confirmed denial is permanent until user action. Never run this probe for endpoints
inside ProxyJump, send credentials through it, or interpret other path failures as
a privacy denial. Unknown results preserve the original failure and retry policy.
Multiple installed builds with the same bundle ID can confuse macOS Local Network
settings (Apple TN3179, FB15568200). For manual permission testing, use the same
signed app copy/path consistently; a grant shown in Settings is not proof that
another copy or Xcode launch is allowed. If retry is still denied after a grant,
quit and reopen that same copy. Never bypass privacy or change bundle/storage IDs
as a workaround. Keep blocked-attempt copy distinct from a live permission query.
Explicit foreground Terminal/Files attempts may use `ConnectionProvider.waitForAccess`
after a typed Local Network failure. SSH waits at most 30 seconds for TCP readiness
of the route's first endpoint and then retries exactly once, with normal server trust.
Do not probe inner jump destinations, send credentials during the wait, or use it
for automatic recovery/background Finder requests. Pending and previously denied
permissions cannot be distinguished by a general public API. Cancellation must be
immediate and late readiness must not restart a cancelled/edited/closed session.
Use the `Farport` scheme for ordinary automatic Run. `Farport Attach` intentionally
waits for an external launch; keep it as a manual fallback, not the default workflow.
See `Docs/Debugging.md` for the shared build path and both workflows.
XcodeGen's post-generation Swift script owns the shared/current-user project
workspace settings and wait-for-launch scheme override; keep it reproducible.
It also canonicalizes only the root local-package navigator entry's cosmetic name,
GUID and ordering: pinned XcodeGen derives those from the checkout directory name.
Do not change the actual XCLocalSwiftPackageReference or package dependencies to
fix that display entry. Run `sh Scripts/verify-project-generation.sh` after generator
changes; it compares generated files in Farport, Harbor and a checkout with spaces.
Keep this regression check and CI's generated-file diff gate enabled.
Use Xcode Default (`UseAppPreferences`), never Legacy (`UseTargetSettings`) or
custom SYMROOT/OBJROOT overrides: SPM rejects legacy build locations. CLI commands
still need `-derivedDataPath Build`; they do not read the IDE's location preference.
If stale standalone Swift modules shadow freshly built package frameworks after
a public Core API change, use a project-scoped `xcodebuild ... -derivedDataPath Build clean`
before changing correct source code. Never clear another project's build data.

`swift test` skips network tests without the fixture. Run the full package suite
against a disposable loopback-only server:

```sh
python3 -m venv /private/tmp/harbor-test-env
/private/tmp/harbor-test-env/bin/pip install -r Scripts/requirements-test.txt
/private/tmp/harbor-test-env/bin/python Scripts/ssh_fixture.py --run-tests
```

For real tmux resume tests, install local tmux (`brew install tmux`) and run the
fixture with `--tmux --run-tests`. It uses a private server socket and home/config,
checks recovery after TCP abort and reloading the saved host, and cleans up only
its own tmux server. Without `--tmux`, these two integration tests are skipped.

The fixture also exposes a loopback packet-dropping proxy. Its printed `blackhole`
path is a test control: while that file exists, packets are discarded without
closing TCP. Never use this control against real connections. Package tests check
the real SSH probe timeout and permanent authentication classification. The Xcode
suite has a live recovery test which starts its own disposable tmux fixture when
`/private/tmp/harbor-test-env/bin/python` is available (otherwise it skips).
It checks automatic reconnect to the same shell PID and that offline input is
not replayed. A second live test checks two independent tab shell PIDs/environments
survive workspace repository reload. Both require tmux and Python fixture dependencies.
The tab restoration test now uses ProxyJump, and a third live test checks recovery
after dropping packets on the gateway transport. `Scripts/jump_fixture.py` is a
forwarding-only gateway with separate credentials/keys, private test DNS aliases,
connection counters, and denial/stall scenarios. Package tests verify SSH/SFTP,
two jumps, binary transfer, independent cleanup, failed auth/forwarding, cancellation
before initial SSH greeting and during jump authentication, and unanswered forwarding
deadlines. Never point these controls or tests at real servers.

Build product: `Build/Build/Products/Debug/Farport.app`. Signing uses the developer's
configured Team (`project.yml`) and Apple Development with automatic provisioning.
Use `-allowProvisioningUpdates` when creating the App IDs/App Group/profiles.
Both app and extension require profiles authorizing `HARBOR_APP_GROUP`.
For compile/unit checks without an account, override `CODE_SIGN_IDENTITY=-`,
`CODE_SIGN_STYLE=Manual`, and `DEVELOPMENT_TEAM=`; this does NOT enable Finder.
The main app (Debug, Release and Local) and File Provider extension use App Sandbox
with outbound network access. Only the main app has user-selected read/write access.
Keep `App/container-migration.plist` bundled; it migrates the complete legacy
Application Support/Harbor directory on first container creation, including workspace
and iCloud queue state. Never migrate only hosts.json or reset a user's container to test.
Panel-selected file access must cover the entire async transfer. Stage downloads using
FileManager's itemReplacementDirectory on the destination volume, not arbitrary siblings
beside a Save Panel URL. No broad filesystem, executable-file, incoming-network or
temporary-exception entitlements in production. Run `xcrun swift Scripts/verify-sandbox.swift`
in CI, and pass a built app/archive product path to verify actual signed entitlements.
The verifier rejects stale extensions/test bundles too. After a target/project rename,
ensure a fresh app bundle is assembled rather than shipping cached old plugins beside
the new extension; use project-scoped build cleanup, never remove real app containers.
See Docs/Sandbox.md for migration/runtime checks. There is no automated distribution pipeline yet.
After an Xcode test action, run a normal build before manual verification or delivery:
the test runner temporarily injects extra signing permissions. Check the signed
extension has no test-only absolute-path read or testmanager Mach-lookup exceptions.

## Verification Expectations

GitHub CI is configured in `.github/workflows/build.yml`: strict lint, loopback
SSH/SFTP/ProxyJump/tmux package tests, and unsigned Debug/Release app builds. No
production secrets or Apple signing material belong in Git or ordinary PR jobs.
Keep package tests on macOS 15 and compile Icon Composer resources on the macOS 26
build host; neither changes the app's deployment target. Preserve asset compilation
failures with pipefail and diagnostic artifacts, never by skipping icon/accent assets.
Keep `Package.resolved`, vendored source/license notes, generated project and shared
schemes tracked. Exclude build output, personal IDE state and `remote_development/`
reference material. See `Docs/CI.md` and `Docs/TestFlight.md` for coverage/release gates.
CI compilation does not establish distribution readiness or validate system permissions.

For UI changes, build and run the app; verify layout, states, and actions using
an isolated library and local fixture, never a user's real server. A Debug build
accepts `--host-library PATH`; the fixture prints a suitable temporary library.
With App Sandbox, that argument alone grants no file access. Prepare the library
inside a disposable app-container location, or use a native panel grant; never add
production filesystem exceptions to read an external fixture path. First-container
migration testing requires a disposable macOS account, not the real user's home.
Fixture terminal commands include `exit`, `drop` (abort TCP), and `eof` (half-close).
Stop fixture processes after testing. Do not interrupt a user's active sessions
just to launch a new build; use a separate test process/library.

The Xcode test scheme must set HARBOR_ISOLATED_TESTS=1 to keep startup migration away
from the real library. Use dedicated Keychain test services/accounts and clean up
only those items. AppTests has its own Info.plist: never inherit NSExtension metadata
from FinderExtension when including its Swift source for callback tests.
That environment flag does not control macOS's container migration before app startup.
Test first sandbox launch/upgrade in a disposable macOS account, never by deleting the
real user's container or letting tests exercise their migrated library. Live hosted tests
spawn external fixture tools and are not evidence of sandbox production permissions;
the unsandboxed package fixture tests remain independent of hosted-test permissions.

Server keys are pinned by hostname/port in Keychain. Unknown/changed keys fail the
handshake without waiting for UI, stop auto-recovery, and prompt only in the main
app. Changes require explicitly forgetting the old pin before trusting the new one;
never silently rotate or downgrade. Finder only reads trust. Verify all ProxyJump
endpoints independently. Tests must pin exported fixture public keys out of band.

Permission and first-use trust are connection requirements, not red transport-error
banners. Terminal and Files own the challenge presentation after transport cleanup.
The verifier itself never schedules UI. Explicit Trust & Connect stores the verified
pin and resumes one original attempt only after the sheet dismisses. Guard callbacks
with the attempt generation and weak model ownership. Cancel/edit/delete/close must
invalidate the callback. Plain Trust Server never starts a connection; changed keys
remain hard blocks. An explicit foreground attempt can wait once for an OS grant;
after timeout or another denial, Retry Connection is manual. Never auto-grant
permissions or start an unbounded retry loop. Preserve terminal history during both steps.
Keep connection-requirement text naturally sized beside the native terminal: vertical
`fixedSize` there can blank the whole split view on macOS 27. `LibraryWindowTests`
checks rendered sidebar pixels during permission/trust/reattach transitions with a
stub iCloud service; model state and accessibility presence alone miss this regression.

For terminal lifecycle changes, cover EOF, transport errors, manual disconnect,
write failure, reconnect, and stale completion/callback protection. Disconnected
terminals must retain output for selection/copy/scroll, hide the cursor, reject
input, and display an explicit persistent disconnected state. Update UI before
awaiting transport cleanup, and invalidate old callbacks when reconnecting.
Sleep/wake events come from NSWorkspace notifications. Pause heartbeats/retries
during sleep; on wake probe any surviving connection first, then reattach tmux
if needed. Do not put the user's Mac to sleep during verification. Use lifecycle
model tests; report separately if real OS sleep/wake or UI verification wasn't run.

For file-transfer changes, preserve staging-file cleanup and existing-destination
protections; test binary round trips, cancellation, and failure paths. Do not use
real remote deletion or overwrite operations for tests.

Finder write tests must cover stable rename identities, same-size/same-mtime conflicts,
lost acknowledgments/restarts, read-only rejection, nonempty-folder protection, and
real atomic replacement/cancellation through the disposable ProxyJump fixture.
Test File Provider callbacks independently; report manual Finder/editor verification
separately rather than equating callback tests with an end-to-end system check.
