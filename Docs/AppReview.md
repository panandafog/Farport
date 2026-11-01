# Public hosts for App Review

These are operator-published shared test/training accounts, not infrastructure we
own. No registration, payment, private account or local server is required. They
can be entered as ordinary hosts in the shipping app. The Debug screenshot mode
also seeds them; Release contains no demo catalog or demo switch.

| Service | Host | Port | Username | Password | Use |
| --- | --- | --- | --- | --- | --- |
| OverTheWire Bandit | bandit.labs.overthewire.org | 2220 | bandit0 | bandit0 | Linux SSH terminal |
| Rebex | test.rebex.net | 22 | demo | password | Limited SSH shell and read-only SFTP |
| Wing FTP | demo.wftpserver.com | 2222 | demo | demo | Backup read-only SFTP; no terminal |

Official sources: [Bandit level 0](https://overthewire.org/wargames/bandit/bandit0.html),
[Rebex demo](https://www.rebex.net/buru-sftp-server/demo/),
[Wing demo](https://www.wftpserver.com/onlinedemo.htm).

## Verification on 2026-10-31

Command-line SSH/SFTP checks used isolated pinned host keys, password authentication,
no SSH agent/private keys and no changes to the user's known_hosts:

- Bandit: password login and interactive PTY; `whoami`, `pwd`, `uname -s`, `ls` succeeded.
- Rebex: password login, interactive shell (`help`, `pwd`, `ls`), SFTP listing and
  download of `/readme.txt` succeeded.
- Wing: password login and SFTP root listing (`download`, `upload`) succeeded.

These are protocol checks, not Farport UI tests. No remote files were written,
renamed or removed. Do not probe other Bandit accounts or publish game solutions.
Recheck availability before submission; these shared services have no availability
agreement with us. Bandit is a learning server, not a dedicated review environment.

The recorded SHA-256 host-key fingerprints were:

| Host | Key | Fingerprint |
| --- | --- | --- |
| Bandit | Ed25519 | `SHA256:C2ihUBV7ihnV1wUXRb4RrEcLfXC5CXlhmAAM/urerLY` |
| Rebex | Ed25519 | `SHA256:d7Te2DHmvBNSWJNBWik2KbDTjmWtYHe2bvXTMM9lVg4` |
| Wing | ECDSA P-256 | `SHA256:6LU1uontQGkpKDMrMF2un6oou43ia8Z6nOHxjwXViNo` |

Rebex/Wing keys also match the HTTPS [Rebex report](https://sshcheck.com/server/194.108.117.16/22)
and [Wing report](https://sshcheck.com/server/108.181.19.185/2222).
Bandit's fingerprint was recorded from the direct connection. Servers can rotate
keys, and Farport may negotiate a different supported algorithm: do not treat this
table as a permanent allowlist or bypass a changed-key warning.

## Suggested App Review notes — iOS/iPadOS

```text
Farport is an SSH client for user-provided servers. No Farport account is required.

To test a real interactive SSH session using a publicly available training account:
1. Tap Add Host.
2. Name: Bandit SSH
   Hostname: bandit.labs.overthewire.org
   Port: 2220
   Username: bandit0
   Authentication: Password
   Password: bandit0
   Session: Standard SSH (not tmux)
   Initial directory: . (default)
3. Save, select the host, and tap Connect.
4. Review the server-key prompt and use Trust & Connect after verifying the key.
5. Try: whoami, pwd, ls, uname -s. Type exit to disconnect.

The account is published by OverTheWire:
https://overthewire.org/wargames/bandit/bandit0.html
This is a shared external training service, not a Farport-operated backend.

Alternative SSH host: test.rebex.net, port 22, username demo, password password.
Use Standard SSH. Its shell supports help, pwd and ls, but is not a Linux shell.
For this limited shell, first turn off Use App Accent in Terminal Appearance.
The iOS/iPadOS version provides terminals; file browsing is macOS-only.
```

## Additional macOS notes

```text
For SFTP browsing/downloading, add:
Name: Rebex SFTP
Hostname: test.rebex.net
Port: 22
Username: demo
Authentication: Password
Password: password
Initial directory: . (default)

Save, select this host and open Files. Review and verify the server-key prompt.
Browse /pub and download /readme.txt.
The server is intentionally read-only; upload, rename and deletion are denied
by the server. This restriction is not an application failure.
Public account details: https://www.rebex.net/buru-sftp-server/demo/

Backup SFTP-only service: demo.wftpserver.com, port 2222, username demo,
password demo. Open Files; an interactive terminal is not supported there.
Public account details: https://www.wftpserver.com/onlinedemo.htm
```

These servers cover real terminal access and read-only file operations. They do
not provide a dedicated writable SFTP account, ProxyJump route or verified tmux
recovery scenario. A complete review of those features may require separate
credentials for infrastructure that permits them. Apple's
[app completeness guidance](https://developer.apple.com/app-store/review/guidelines/#app-completeness)
asks for full access to the app's functionality; these accounts alone do not
guarantee review acceptance.
