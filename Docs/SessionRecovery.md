# Session Recovery Options

Status: tmux resume, in-memory history, heartbeat, bounded automatic tmux reconnect,
sleep/wake handling, multiple terminal tabs, and local workspace metadata persistence
are implemented. Local transcript persistence remains a proposal.

## Three Different Things

1. Terminal history: bytes/text already received and rendered by the client.
2. Workspace state: open hosts, selected view, directory, tab order, terminal size.
3. Remote execution: shell processes, jobs, environment, editor state, working directory.

Restoring the first two does not restore the third. A new SSH connection creates
a new shell unless it explicitly attaches to a surviving server-side session.
A process can sometimes outlive its connection, but ordinary SSH provides no
generic way to reattach its old PTY. Never replay command history automatically:
commands can have irreversible side effects, and history can contain secrets.

## Recommended Next Steps

### 1. Local Workspace (Implemented) And History Persistence (Future)

`WorkspaceRepository` stores schema-1 metadata in `hosts.workspace.json`, separate
from the host/credential library. Each host has ordered tabs with stable UUIDs and
names, selected tab, and Terminal/Files mode; the document stores selected host.
Changes save atomically immediately and on quit. Missing hosts are ignored/pruned,
invalid/duplicate tab identities and future schemas are rejected, and load failure
disables writes so damaged metadata is not silently replaced. Restoring makes no
network requests and never restores automatic-reconnect intent. Models create
native terminals lazily and retain their buffers while switching tabs/hosts/views.

Closing a tab removes its metadata and detaches SSH without killing tmux. Editing
a host preserves tab identities but detaches existing connections. This first
workspace version does not persist SFTP directory, terminal geometry, or transcripts.

Extend the versioned repository with terminal dimensions, timestamps, and a bounded
local transcript in a future iteration, without persisting a false connected status.
After restart, restore these sessions as **disconnected**, with a reconnect action.
For plain SSH, reconnect starts a new shell with a visible history boundary.

Start with a text scrollback snapshot and a separate read-only history viewer.
It is simpler and safer than treating arbitrary recorded ANSI output as executable
input to a live terminal emulator. Exact interactive-screen replay additionally
needs resize events, normal/alternate buffers, cursor/modes, and parser state.
Never let replay send terminal responses, clipboard writes, hyperlinks, or other
side effects to the network or OS. Do not record raw keyboard input, particularly
passwords entered into programs which suppress echo.

Checkpoint periodically and on lifecycle events using atomic writes; graceful
termination alone is insufficient for crashes. Bound disk usage, provide clear/
disable-history controls and retention settings, and keep transcripts out of
iCloud by default. Transcripts themselves may contain secrets; file permissions
are not encryption. Encryption can follow alongside Keychain work.

### 2. Optional Server-Side tmux Sessions (Implemented)

The host's Terminal > Session setting opts its terminal tabs into independently
named tmux sessions on the server. Reconnecting SSH attaches to the same live shell,
including its current directory, running programs, and environment. This also
works after a Harbor restart and can support macOS/iPadOS clients attaching to the
same remote session. [tmux documentation](https://github.com/tmux/tmux/wiki)

Requirements and boundaries:
- tmux must already be installed, or installation must be an explicit user action.
- Persist a generated session identifier, not a shell command supplied by a host name.
- Use validated identifiers/quoting when invoking server commands.
- Distinguish Disconnect/Detach from End Remote Session; never kill it implicitly.
- Provide a fallback to ordinary SSH when tmux is unavailable, without claiming resume.
- Remote history and local transcripts differ; tmux history limits still apply.
- Server reboot or tmux termination loses running jobs. Plugins can reconstruct
  layouts/commands, but cannot generally resurrect arbitrary process memory.

`TerminalResumeStrategy` selects standard SSH or tmux. `TerminalLaunchPlan` in the
SSH adapter constructs a POSIX shell command with only a UUID-derived session
identifier; profile labels and paths never enter that command. Citadel allocates
a PTY and sends an exec request, rather than typing into an interactive shell.
`tmux new-session -A -s harbor-<UUID>` creates or attaches without evicting other
clients. The wrapper uses `/bin/sh` so non-POSIX login shells can launch it too.
Exit 127 reports an actionable missing-tmux error, with no silent plain-shell fallback.

Persisted tab UUIDs supply identity across restarts and label changes. The first
default tab uses its host UUID to reuse the pre-tabs remote session. Additional
tabs get new UUIDs, passed separately from the saved host through the provider
contract; never mutate a host UUID to select a terminal session.
Libraries migrate schemas 1/2/3/4 to Keychain-backed schema 5; missing strategy on a legacy profile
defaults to standard SSH. A mode change never kills the previous remote session.
There can be multiple independent persistent sessions per saved host.
Detach and app quit close SSH only. To end a shell, use `exit` inside it; the last
pane closing ends tmux. Full local scrollback persistence is still separate work.

### 3. Connectivity Detection And Reconnect Policy (Implemented)

Alongside EOF and transport errors, the client performs an authenticated SSH
session-channel open/close round trip every 15 seconds. This sends no command and
does not touch the interactive shell. OPEN_FAILURE is also a valid liveness
response, important on servers with MaxSessions limits. With no response in
10 seconds, close the transport. Timeout and cancellation release pending requests.
This gives approximately 25-second silent-failure detection while the app runs;
it is not immediate Wi-Fi-change detection or a guarantee while the OS suspends it.

`TerminalConnectionError` separates transient transport/timeouts from permanent
authentication, host-key, and configuration errors. `ConnectionRecoveryPolicy`
holds portable timing/backoff defaults. An established tmux terminal retries after
1/2/4/8/16/30 seconds, with finite attempts and visible cancellation/countdown.
Connections which open and immediately fail do not reset the budget: a successful
heartbeat is required. Explicit Detach/Cancel, terminal EOF/normal completion,
permanent errors, or exhausting the budget stop recovery. Plain SSH does not
automatically start a replacement shell, and terminal keystrokes are never replayed.

NSWorkspace sleep notifications pause heartbeat and retry tasks and disable input.
Wake checks an existing transport first; if it is dead, reattach tmux. If a retry
was pending during sleep, wake restarts a fresh bounded recovery sequence. A user
detach cancels this intent. The UI state is invalidated before awaiting cleanup,
so old input, probe, and connection callbacks cannot overwrite a new session.

Tests combine controlled model transports with an independent AsyncSSH server,
real tmux, and a loopback proxy which drops packets without closing TCP. The live
Xcode recovery test verifies the original shell PID and environment survive a
heartbeat failure and automatic reattachment. Sleep/wake logic is model-tested;
testing it does not put the user's Mac to sleep.

ProxyJump reconnect opens the entire saved route before reattaching the final
tmux session. Gateway profiles supply only SSH transport/authentication, never
shell or tmux requests. Each tab and SFTP connection owns its own route, so closing
one cannot close another's gateway transport. Gateway editing disconnects all
dependent sessions and refreshes route settings while retaining their local buffers.
The live recovery test also drops packets between the client and gateway, verifying
the original destination shell PID/environment after automatic route reconstruction.

### Other Options

**Mosh:** useful later for roaming and intermittent Wi-Fi/mobile networks. It uses
SSH to start a server component, then UDP; it needs server support and firewall
access. It is terminal-only, not an SFTP replacement, and is not by itself a
complete app-restart/workspace persistence solution. Assess licensing and the
embedded client implementation before committing. [Official Mosh site](https://mosh.org/)

**macOS connection helper:** an XPC/helper process could own a connection across
GUI restarts, but adds IPC, lifecycle, signing, and crash-recovery complexity. It
does not survive machine reboot/network loss and is not a reusable iOS background
execution strategy. Not recommended for this MVP.

Next: improved SFTP workflows; local transcript persistence remains separate work.
Mosh and a persistent helper should remain separate later decisions.
