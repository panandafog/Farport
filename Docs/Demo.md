# Screenshot and presentation mode

For prepared screen arguments, device/language presets and FramePilot commands,
see [FramePilot integration](FramePilot.md).

Select **Farport Demo** (macOS) or **Farport iOS Demo** (iPhone/iPad/Duo) in Xcode
and Run. Both use Debug with `--demo`. The five fictional hosts need no server,
internet access, SSH credentials, Mac Local Network permission or Mac-to-iPhone connection. The initial
host terminal connects automatically; on a compact iPhone navigate to Production API.
Choose the Logs / Deploy tabs or another host and press Connect to load their sample
terminal, or open Files on macOS to vary the scene.

The five fictional hosts use reserved `.example` domains. The first host has Shell,
Logs and Deploy tabs. Terminal output, directory listings and dates are deterministic.
The sample shell supports `help`, `ls`, `ls -la`, `pwd`, `cd src`, `cd ..`, `cd`,
`cat README.md`, `git status`, `docker ps`, `logs`, `uptime`, `uname -a`, `clear`,
`exit`, Ctrl-C, Ctrl-L and backspace. Escape sequences are discarded. This is a
small simulation, not a shell, SSH server or tmux implementation; it never executes
input or contacts any host for fictional/added entries, even after editing their addresses. Unknown commands print
help guidance. Each Connect starts a fresh sample shell.

For fictional hosts, the Mac file browser uses an in-memory file tree per host. Browse, create folders,
rename, remove files/empty folders, upload (up to 1 MB) and download small examples.
Only explicitly selected upload sources/download destinations touch local files.
The terminal transcript is independent of file-browser edits. Finder integration and
iCloud are unavailable in demo mode; mobile remains terminal-only.

Profiles and workspaces are memory-only and reset on every launch. Real host
libraries, keys, server pins, Finder locations and CloudKit are not loaded by the
demo factory. Both platforms use a memory-only trust store for public connections. Test isolation
(`HARBOR_ISOLATED_TESTS=1`) takes precedence over --demo. The existing simulator SSH
fixture remains available separately for actual transport testing.

With the default **Use App Accent** setting, the sample prompt, banner and directory names use the application accent
through the optional terminal-decoration colors, including the system's chosen
macOS accent. Semantic success/log statuses keep their ANSI green. No ANSI palette
slots are remapped. Accent changes affect subsequent sample prompts/listings without
rewriting output already in the scrollback; reconnect refreshes the sample screen.
Real SSH prompts are supplied by the remote shell and are not modified by this demo.

Use the app's normal appearance preferences for light/dark and color schemes.
In Edit Scheme > Run > Options choose App Language for English/Russian captures.
Appearance preferences still belong to the app's normal device-local UserDefaults.
To present the shipping experience, use ordinary terminal/file interactions and
avoid claiming the simulated output verifies network connectivity or performance.

## Release exclusion

All FarportDemo implementations/data and app --demo handling are compiled only under
`#if DEBUG`. Release/TestFlight has no entry point, hidden menu or switch to enable
it. Demo schemes also archive as Release. Building with the demo scheme therefore
does not ship the sample catalog in an archive. Do not add DEBUG to Release settings.

After building Release, run:

```sh
python3 Scripts/verify-demo-release.py Build/Build/Products/Release/Farport.app
python3 Scripts/verify-demo-release.py Build/iOSCompatibility/Build/Products/Release-iphoneos/Farport.app
```

Both CI platform builds enforce this bundle-content check. Debug provider tests run
with `swift test --filter FarportDemoTests`; no UI tests or real accounts are involved.

## Real remote testing

For real SSH/SFTP/tmux, use the disposable local fixtures documented in AGENTS.md.
An iOS Simulator can reach the Mac's loopback fixture; a physical iPhone's localhost
is the phone itself. The offline demo works unchanged on both.

Three entries prefixed **Public ·** follow the fictional hosts: Bandit SSH, Rebex
SSH/SFTP and Wing SFTP. They make real network connections only when explicitly
connected/opened; the startup screenshot remains offline. Published public credentials
are prefilled. The ordinary first-use trust sheet is required, and trusted pins last
only for this demo launch. No Keychain access, Finder domains or cloud sync is enabled.
Only these exact catalog identities/endpoints/credentials/routes/session modes can
reach the injected transport; editing those settings fails rather than contacting
another server or pretending the connection succeeded. Names, notes and tab metadata
can change. New/fictional hosts always use the simulation.

Wing is SFTP-only: use Files on macOS; its terminal shows an explanatory error.
Bandit and Rebex use Standard SSH, with no tmux dependency. Public availability,
output and read-only restrictions belong to their operators. Never upload private
files or expect a dedicated machine. See [App Review connection notes](AppReview.md)
for exact accounts, tested capabilities, limitations and ready-to-paste instructions.
