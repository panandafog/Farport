# Native ProxyJump

Implemented using the vendored Citadel `SSHClient.jump(to:)`, not an OpenSSH process
or a second `ssh` command typed into a gateway shell. macOS is verified; the shared
Core/SSH implementation imports no AppKit and does not depend on macOS subprocesses.
iOS/iPadOS applications remain unimplemented and unverified.

## Model And Storage

`HostProfile.jumpHostIDs` is an ordered array of references to saved hosts. Each
endpoint keeps its own username, authentication method, and credentials. The host
repository migrates schemas 1/2/3/4 to schema 5 with Keychain references. Missing route
data on legacy profiles means direct connection; older app versions reject newer schemas instead of ignoring
the route and accidentally connecting directly.

`ConnectionRoute` resolves references against a snapshot of the host library,
expanding any gateway's own route before that gateway. It rejects missing nodes,
duplicate library IDs, repeated route nodes, cycles, non-SSH gateways, and routes
longer than eight endpoints including the destination. A target supplied by the
editor overrides its saved copy during validation. All validation runs before SSH.

The UI exposes one gateway selector per host. Nested gateway profiles allow longer
chains. Saving retains an existing explicit ordered array unless the selector is
changed; selecting a different gateway replaces it with that single reference.
Candidates that create cycles are excluded. A missing selected gateway stays
visibly unavailable, not silently replaced with Direct connection.

## Transport And Ownership

`SSHRouteConnector` establishes the first SSH transport, then opens direct-tcpip
channels to subsequent endpoints and performs SSH authentication inside them.
Destination names are passed unchanged to the preceding gateway, so corporate DNS
does not have to work on the Mac. No key is copied to a gateway, no SSH agent is
forwarded, and no local port is opened. Only the final connection receives PTY,
tmux exec, SFTP, or heartbeat requests, regardless of a gateway's terminal mode.

Each terminal/file connection owns an `SSHConnection` containing the leaf client
and every parent client. Close proceeds in reverse order. Initial route failure
cleans up every completed parent; a rejected nested handshake is cleaned up by
closing its parent. A small Citadel patch closes failed initial TCP handshakes
and supports cancellation of the initial connection before SSH greeting/auth.

Every jump has a 15-second overall deadline, covering both direct-tcpip channel
creation and nested authentication. Deadline/cancellation closes the parent to
unblock pending NIO futures; failure cleanup then closes earlier parents. Initial
TCP has a 15-second connect timeout; Citadel's existing SSH login timeout is 10 seconds.
No route connections are pooled between terminals or SFTP in this MVP.

## Errors And Recovery

`TerminalConnectionError.route` adds endpoint context without losing the nested
error's retry classification. Bad credentials/keys, route/configuration errors,
and rejected forwarding are permanent and require manual retry. The underlying
NIO API does not expose structured forwarding rejection reason codes; Harbor shows
its diagnostic and asks to check both forwarding permissions and destination
reachability. It does not parse diagnostic strings to guess retry policy.

Transport/timeouts remain transient. An established tmux terminal reconstructs
the full route before attaching its unchanged tab UUID. A clean exit, manual
Disconnect/Detach/Cancel, or permanent error stops retry. Standard SSH never
automatically starts a replacement shell. Transfers are not automatically replayed.

Changing a host refreshes all transitive dependents using the new library snapshot,
disconnecting their old transports and cancelling retry intent. Their tabs, terminal
instances, and in-memory scrollback remain available. Unrelated sessions are left
alone. Referenced gateways cannot be deleted until their routes are changed.

## Verification And Limits

The disposable AsyncSSH gateway rejects shell/subsystem requests and forwards only
allowlisted private DNS aliases to loopback fixture endpoints. It tracks open
connections and supports denied forwarding, unanswered requests, stalled handshakes,
and a gateway-side packet-dropping proxy. Tests use distinct gateway/destination
passwords and private keys; there are no real credentials or real server operations.

Package tests cover SSH input/resize, remote DNS, SFTP binary upload/download,
two gateways, independent connection cleanup, stage errors, timeouts, and cancellation.
Core tests cover validation/schema migration; app tests cover saved-host dependency
lifecycle/history and tmux recovery/tab restoration through the gateway.

This is not a complete OpenSSH configuration engine. `~/.ssh/config`, SSH agent,
ProxyCommand, HTTP/SOCKS proxies, MFA/keyboard-interactive authentication, and a
generic local-port-forwarding UI are not implemented. Credentials now use Keychain,
and every gateway/destination uses explicit host-key pinning. See [Security](Security.md).
Nothing is installed or configured on a gateway or destination implicitly.
