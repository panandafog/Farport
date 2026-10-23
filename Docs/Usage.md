# Harbor Usage And Implementation

Native macOS SSH/SFTP client MVP. Requires macOS 15 or later.

## Included

- Saved hosts: name, hostname, port, username, authentication, password or imported
  OpenSSH private key, key passphrase, initial remote directory, and notes.
- Keychain-backed credentials with migration from old plaintext libraries; explicit
  server-key trust and changed-key rejection for SSH, SFTP, Finder, and ProxyJump.
- Opt-in iCloud host-profile sync, including ProxyJump references, offline changes,
  deletion propagation and recoverable conflict copies. Credentials remain device-local.
- Password, Ed25519 and RSA key authentication, including encrypted OpenSSH keys.
- Interactive SSH terminal with ANSI rendering, input, clipboard paste, and PTY resize.
- Automatic system light/dark terminal appearance, with readable ANSI-16 palettes,
  matching cursor/selection colors, and unchanged 256-color/true-color output.
- Explicit disconnected status, end time, and manual reconnect, with in-memory
  terminal history retained after EOF, transport failure, or manual disconnect.
- Multiple named terminal tabs per host, with creation, switching, rename, and close.
- Optional per-tab tmux sessions: detach and reattach to a persistent remote
  shell after connection loss or restarting Harbor.
- SSH heartbeat with finite timeout, bounded automatic tmux reconnect, cancellation,
  and connection verification after waking the Mac.
- Native ProxyJump for both SSH and SFTP, with saved-host routes and independent
  authentication at each endpoint. Destination names resolve from the gateway.
- SFTP browsing, hidden files, individual-file upload/download with progress and
  cancellation, folder creation, rename, and deletion of files or empty folders.
- Optional read-only or read/write Finder locations backed by SFTP, including
  ProxyJump, on-demand downloads, uploads, atomic saves, rename/move, conflict
  copies, retained system cache, and refresh of visited folders.
- Separate terminal and file sessions; switching hosts or views keeps sessions alive.
- Host editing, deletion, search, and persistence across launches.
- Workspace restoration: tab names/order/identities, selected host/tab, and selected
  Terminal/Files view. Restored terminals remain disconnected until explicitly attached.

## Run

Open `Harbor.xcodeproj`, select the Harbor scheme and My Mac, and run.
Finder requires Apple Development signing and an App Group. The project preserves
the configured developer Team; other developers must select their own Team and
register the generated `group.dev.harbor.shared.<Team ID>` App Group. Its value is
configured once as `HARBOR_APP_GROUP` in `project.yml` and passed to both targets.
Both the app and its extension need matching provisioning profiles.
Their bundle identifiers are `com.panandafog.harbor` and
`com.panandafog.harbor.finder`. Shared App Group/Keychain identifiers intentionally
retain their original names to preserve data access. Finder locations registered
under the previous extension ID may need to be connected again with the new app.
The Harbor app also needs iCloud/CloudKit (`iCloud.com.panandafog.harbor`) and Push Notifications.
See [iCloud setup and behavior](iCloud.md). For development without CloudKit
provisioning, use the `HarborLocal` scheme (`Local` configuration); iCloud is disabled
in that build, while shared Keychain and Finder signing are retained.
The first build downloads Swift Package dependencies.
Install SwiftLint first (`brew install swiftlint`); every Xcode build runs lint.

macOS requires separate Local Network approval for LAN servers, including `.local`
hostnames. Allow Harbor when prompted; a foreground Terminal/Files attempt waits
up to 30 seconds and retries once when the route's first endpoint becomes reachable.
Cancel stops the pending attempt. If the wait expires, use **Retry Connection**.
A pending permission is guidance, not a red connection-failure banner.
Review access in **System Settings > Privacy &
Security > Local Network**; a changed bundle ID may require new approval. This is
independent of the sandbox/network entitlement and SSH server-key trust. Connection
errors retain TCP/DNS details; a route error alone does not prove permission denial.
For a direct no-route error, Harbor performs a one-second, cancellable TCP-only
check using Network.framework to distinguish a confirmed Local Network denial.
It sends no SSH credentials and never probes destinations behind ProxyJump locally.

```sh
xcodebuild -quiet -project Harbor.xcodeproj -scheme Harbor \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath Build -allowProvisioningUpdates build
open Build/Build/Products/Debug/Harbor.app
```

`project.yml` is the XcodeGen source of truth. After changing project configuration,
regenerate with `xcodegen generate`. The generated Xcode project is included, so
XcodeGen is not required just to build.

## Architecture

| Layer | Responsibility |
| --- | --- |
| `Sources/HarborCore` | Platform-neutral models, host/workspace repositories, session contracts, paths |
| `Sources/HarborSSH` | Citadel/SwiftNIO implementation of SSH and SFTP, transfer lifecycle |
| `Sources/HarborSecurity` | Shared Data Protection Keychain adapter |
| `Sources/HarborCloud` | CKSyncEngine private-database sync, encrypted records, durable queue |
| `Sources/HarborFinder` | macOS File Provider items/errors and shared-container access |
| `FinderExtension` | Sandboxed replicated File Provider, mutations, and enumerators |
| `App` | macOS SwiftUI views, session state, AppKit file panels, SwiftTerm terminal |
| `Vendor/Citadel` | Pinned library with small interoperability fixes documented in `UPSTREAM.md` |

The shared Swift package declares macOS 15 and iOS 17 support and imports no AppKit.
iOS/iPadOS apps are not implemented or validated yet. They can reuse the core and
transport with platform-specific terminal adapters, file pickers, and navigation.

`ConnectionProvider`, `TerminalSession`, and `RemoteFileSession` separate the UI
from transport. Host profiles carry independent terminal/file provider identifiers.
Additional protocols can implement the file-session contract and be routed by a
composite provider without changing the file browser. Capability-specific UI
(for example, object-store rename semantics) should be added with those adapters.

`HostRepository` isolates storage from UI. `HostProfile` and `HostCredentials` are
separate values, persisted through independent metadata and secret stores without
changing transport code. Keychain credential storage and optional iCloud profile sync
are implemented. Schema versioning prevents silently overwriting newer data.

## MVP Storage And Limits

Hosts persist at `~/Library/Application Support/Harbor/hosts.json` (not just RAM).
Schema 5 stores profiles, device-local credential readiness and Keychain references,
not passwords/private keys/passphrases.
Legacy libraries migrate only after secrets are stored and read back successfully.
Finder snapshots use the same shared Keychain with independent references. Missing
secrets or signing entitlements are errors; there is no plaintext fallback. Profile
metadata is also kept in local JSON with owner-only permissions. iCloud is off by
default; enabling it explicitly merges profiles with the current account. Imported
hosts require credentials on each device. Endpoint/authentication/route changes
require reviewing credentials before reconnecting. Server trust is never synced.

Unknown server keys require explicit fingerprint confirmation; changed keys block
the connection. Each gateway and destination has its own hostname/port pin. Use
**Security > Server Keys** to inspect or forget pins. For a first terminal/Files
connection, verify the fingerprint and choose **Trust & Connect** to store the pin
and resume that attempt. Cancel never retries. Finder setup offers **Trust Server**
and requires retrying setup; the background extension never approves keys.
See [Security](Security.md)
for migration, trust policy, and limits. Main-app sandboxing, notarized
distribution, and an independent security audit are not implemented.

Workspace metadata lives beside the host library in `hosts.workspace.json`. It has
no credentials or terminal transcript. Changes are saved atomically as they occur,
not only on clean app exit. Corrupt or newer workspace files are reported and kept
untouched; move the affected file aside and restart to begin a fresh workspace.

No SSH agent, ssh_config import, HTTP/SOCKS proxies, recursive delete, transfer resume,
or synchronous Finder disk mounting yet. The existing Files UI transfers individual
files and rejects existing remote destinations. Finder can create folders and copy
their contents through per-item uploads. Remote uploads use a temporary sibling and
rename on completion. Finder saves use a separate atomic replacement capability,
requiring the OpenSSH POSIX rename extension and checking a content fingerprint.
Downloads stage locally before replacing the chosen destination. Cancellation tries
to clean staging files; a broken connection can leave remote `.part` files behind.

## Tests

Style checks use the standard SwiftLint rules plus a few focused opt-ins. Warnings
fail the check; vendored and generated code is excluded. Contributor instructions,
project plans, and build/test procedures are in [AGENTS.md](../AGENTS.md).

```sh
sh Scripts/lint.sh
xcodebuild -quiet -project Harbor.xcodeproj -scheme Harbor \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath Build test
```

The Xcode test target verifies terminal state, history retention, reconnect, stale
completion handling, and input/write-failure behavior using controlled transports.

```sh
swift test
```

This runs model/storage and launch-plan tests and skips network tests unless the
local fixture is provided. Run the package suite against an independent AsyncSSH server:

```sh
python3 -m venv /private/tmp/harbor-test-env
/private/tmp/harbor-test-env/bin/pip install -r Scripts/requirements-test.txt
/private/tmp/harbor-test-env/bin/python Scripts/ssh_fixture.py --run-tests
```

The fixture binds loopback on an ephemeral port, creates disposable files and keys,
and shuts down after tests. It checks authentication failures, password and three
key variants, interactive PTY input/resize, binary round trips, local replacement,
remote collision handling, cancellation cleanup, rename, and deletion.
It also checks shell exit, remote EOF without channel closure, and TCP abort.

To include real tmux persistence and missing-tmux tests:

```sh
brew install tmux
/private/tmp/harbor-test-env/bin/python Scripts/ssh_fixture.py --tmux --run-tests
```

The tmux fixture uses its own server socket and config/home directory. It verifies
the same shell PID, environment, working directory, and a surviving background job
after TCP abort and loading the host from disk. It never uses or kills your normal
tmux server. The fixture also tests heartbeat timeout using a proxy which silently
drops packets while keeping TCP open. Xcode adds terminal/recovery model tests and
live automatic-recovery and independent-tab restoration tests which start their
own fixtures when the Python test environment above exists. These require tmux
and skip if that environment has not been prepared.

For manual UI testing, run the fixture without `--run-tests`; it prints a temporary
host-library path. A Debug build accepts `--host-library PATH` to avoid touching
your normal library. The fixture password and keys are disposable, not production
credentials. Do not use that override with real credentials in a shared directory.

## Finder

Use **Finder connections** in the host header, then **Connect Folder to Finder**.
Choose a remote directory and **Read Only** or **Read & Write** access; macOS may
show an Enable button for the new provider. Existing connections stay read-only;
connect a new writable location explicitly to enable uploads.
The menu also provides Open, Refresh, and Disconnect for saved Finder locations.

Writable locations support file/folder creation, saving, rename/move, and deletion
of files or empty folders. Conflicting saves keep the local edit in a remote
`Harbor conflict` sibling instead of replacing a changed server file. Nonempty
folder deletion, symlinks, and combined rename plus content update are unsupported.
Finder uses on-demand local copies, not a
synchronous SFTP disk. The extension can continue serving an explicitly connected
location while Harbor is closed. Disconnect preserves downloaded data locally;
it is not a secure erase. See [Finder design and limits](Finder.md).

## ProxyJump

Save the gateway as a normal host with its own username and credentials. In the
destination's **Edit Host > Connection > Connect through**, select that gateway.
Leave the destination's real hostname, SSH port, username, and credentials in its
own profile. **Direct connection** explicitly disables jumping for that profile.
The route is shown below the destination address and applies to Terminal and Files.

Harbor opens an SSH direct-tcpip channel through the gateway and authenticates a
separate SSH connection to the destination inside it. No gateway shell, tmux,
agent forwarding, copied keys, or local listening port is needed. The gateway must
permit TCP forwarding and reach/resolve the destination. A gateway's own saved
route can supply additional hops (eight endpoints maximum including destination).

Every terminal and SFTP connection owns its own chain. Cancelling/disconnecting
closes the destination then the gateways. tmux reconnect rebuilds the chain and
attaches the same tab session. Authentication, configuration, and forwarding-rejection
errors stop retries; the error names the failed endpoint. Forwarding rejection can
mean either denied permissions or an unreachable destination; fix it and retry
manually. Silent transport failures/timeouts use the existing bounded retry policy.

Saving a gateway disconnects dependent sessions and refreshes their route without
discarding tabs or local terminal output. Deleting a referenced gateway is blocked.
Routes persist in host-library schema 5; legacy schema 3/4 routes are preserved during
Keychain migration, and older profiles without route data default to direct access.
There is no automatic direct fallback, and `~/.ssh/config` aliases are not imported.
See [ProxyJump implementation](ProxyJump.md) for lifecycle and verification details.

## Session Recovery

In **Edit Host > Terminal > Session**, choose **Persistent (tmux)**. The server must
already provide tmux in the SSH account's PATH. Harbor creates or attaches to a
session named `harbor-<tab UUID>`. The generated name is available in the terminal's
tmux badge tooltip. The first default tab reuses the old host UUID for compatibility.
Renaming a host or tab does not change its server session. Every new tab has its
own identity, so terminals on the same host do not share the same shell.

**Detach** disconnects SSH while remote programs keep running. **Attach** reconnects
to the same remote shell; it also works after restarting Harbor and selecting the
same saved host. `exit` ends the current shell/pane; closing the last pane destroys
the tmux session. A later Attach then creates a fresh session. Deleting a saved host
does not kill its remote session. Other attached tmux clients are not evicted.

The server's tmux configuration and history limits apply. Its current screen and
server-side scrollback survive while that tmux server is alive; use tmux copy mode
to inspect older remote history. Local terminal output is still only in memory:
this feature does not persist local scrollback. Open tabs are restored separately.
Server reboot,
session termination, or server settings which destroy detached sessions can end it.

Use the plus button or Command-T for a new tab; rename via its context menu and
close with its x button. Command-Shift-[ / ] switch tabs. Closing removes the tab
from the saved workspace and detaches its connection, but does not kill tmux.
After restarting Harbor, Attach returns each restored tmux tab to its own shell.
Standard SSH tabs also restore, but Connect starts a new shell. No commands are replayed.

Every connected SSH terminal is checked every 15 seconds using an authenticated
SSH channel open/close round trip with a 10-second timeout. This does not execute
commands or send heartbeat bytes into the shell. A response rejecting the temporary
channel also proves the server is alive. Silent packet loss is normally detected
within about 25 seconds while the app is running, independent of terminal output.

For an established tmux session, transient transport loss automatically retries
attachment after 1, 2, 4, 8, 16, and 30 seconds (plus connection/handshake time).
The UI shows Reconnecting, attempt count, countdown, and Cancel. Input during
disconnection is ignored, never queued or replayed. Six consecutive failed attempts
stop recovery; a successful heartbeat renews that retry budget. Initial connection
failures before a terminal is opened require a manual retry.

Detach/Cancel, clean shell exit/tmux detach, missing tmux, authentication errors,
configuration errors, and host-key verification failures do not auto-retry.
Unknown or changed server keys stop recovery until explicitly reviewed in Harbor.
Standard SSH detects loss but requires manual reconnect to create a new shell.

While the Mac sleeps, heartbeat/retry timers pause. After wake, Harbor first checks
the old connection; if it has failed, tmux reconnects use the existing server
session. Detaching during recovery cancels it, including any wake-triggered retry.
Automatic recovery is terminal-only; file transfers are not automatically replayed.
See [Session recovery options](SessionRecovery.md) for local workspace/history
persistence, the tmux implementation, reconnect policy, and Mosh trade-offs.

## Dependencies

- [Citadel](https://github.com/orlandos-nl/Citadel), MIT, vendored revision recorded
  in `Vendor/Citadel/UPSTREAM.md`.
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), MIT, pinned to 1.10.1.
- SwiftNIO, Swift Crypto, and the Citadel-compatible SwiftNIO SSH fork, resolved by SPM.

Dependency licenses remain with their respective source packages.
