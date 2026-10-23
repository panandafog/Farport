# Citadel

Vendored from https://github.com/orlandos-nl/Citadel at
`ae8562f895de06ccb86fdb1cbb65fd99c8976e12`, under the included MIT license.

Local changes:
- Add the negotiated OpenSSH `posix-rename@openssh.com` SFTP request for atomic
  replacement. Ordinary SFTP v3 rename remains no-overwrite. Independent AsyncSSH
  tests cover existing-file replacement and failed preconditions; no delete/rename fallback.
  This is client-only support; the vendored server does not advertise this extension.
- Close an established TCP channel when the initial SSH handshake/authentication
  fails; cancellation also closes the in-flight initial channel. Route failure
  tests cover rejected gateway authentication and cancellation before SSH greeting.
- SFTP v3 RENAME must not encode the v5 flags field. Strict servers reject the
  extra bytes with SSH_FX_BAD_MESSAGE. Harbor's independent AsyncSSH integration
  test covers upload finalization and rename.
- SFTP directory enumeration closes the remote directory handle and validates
  the final status instead of leaking it until the subsystem is closed.
- PTY cleanup tolerates an already closed channel and preserves the original
  stream error instead of masking it with an AlreadyClosed error.
- The command handler finishes output on channel inactivity and remote EOF, not
  only on handler removal. Integration tests cover shell exit, TCP abort, and an
  EOF-only peer which waits for the client to close its channel.
- `withPTY` accepts an optional command and sends an SSH exec request after PTY
  allocation. Harbor uses this to attach to tmux without typing commands into an
  interactive login shell. The default still requests an ordinary shell.
- `checkConnection(timeout:)` performs an authenticated SSH session-channel
  open/close round trip without a shell/exec request. OPEN_FAILURE also proves
  liveness, so MaxSessions limits do not imply disconnection. Timeout/cancellation
  closes the parent transport and releases pending requests. A completion guard
  handles timeout/close races. Independent tests use a silent packet-loss proxy.

The package manifest exposes the library only; example executables and upstream
test targets are not included. Revisit these patches when updating upstream.
