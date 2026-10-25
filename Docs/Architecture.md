# Shared Architecture

Farport has macOS and terminal-only iOS/iPadOS apps. Its reusable Swift package targets
macOS 15 and iOS/iPadOS 17. `Scripts/verify-ios.sh` compiles shared libraries against the
iOS Simulator SDK and builds the mobile app for devices in Debug/Release. Unsigned
compilation does not validate device provisioning or background/network permissions.

## Boundaries

- **FarportCore**: host/route/workspace models, repository contracts, credential and
  trust contracts, sync merge rules, remote file operations and Finder catalog rules.
  No AppKit, UIKit, SwiftUI, SwiftTerm, Citadel or CloudKit imports.
- **FarportSessions**: observable terminal state/recovery, file browser operations,
  trust prompts, tab workspaces and iCloud coordination. Uses Foundation/Combine and
  the shared contracts, without native views or a concrete transport dependency.
- **FarportLocalization**: shared English/Russian resources and formatting.
- **FarportSSH**, **FarportSecurity**, **FarportCloud**: concrete transport, Keychain
  and CloudKit adapters. Apple frameworks remain here; these are not Linux targets.
- **FarportFinder** and **FinderExtension**: macOS File Provider integration.
- **App**: macOS composition, SwiftUI views, native dialogs, clipboard, terminal
  renderer/theme and NSWorkspace lifecycle hooks.
- **SharedUI**: cross-platform host editing, trust/cloud presentation and terminal colors.
- **iOS**: adaptive native navigation, UIKit terminal and scene lifecycle.

`App/LibraryEnvironment.swift` assembles the real macOS repositories and services.
`HostLibraryModel<Terminal>` owns host CRUD, workspace persistence, route invalidation
and synced-profile application. The macOS wrapper injects Finder revocation through
HostLibraryIntegration; MobileLibraryModel has no Finder dependency.

## Terminal And Lifecycle

`TerminalSessionModel` owns connections, attempt generations, input gating, heartbeat,
retry budget and trust/access requirements. `TerminalOutput` accepts bytes, cursor
visibility and focus requests. It never resets the screen. macOS `TerminalModel` is
a thin SwiftTerm/AppKit adapter; `MobileTerminalModel` implements the same contract with UIKit.

Connection errors retain the failing saved-host ID through endpoint/route wrappers.
Terminal and file models expose `settingsHostID` for authentication/configuration
errors; the UI opens that host's editor, including a failed ProxyJump gateway. Never
infer recovery actions by matching localized error text. Editing settings clears stale
diagnostics while preserving terminal buffers. Permission and server-trust failures
keep their dedicated actions.

`SessionWorkspace<Terminal>` receives a terminal factory. It keeps per-tab controller
identity, so switching views does not rebuild the native terminal or lose scrollback.
Restoration retains metadata/UUIDs, stays disconnected and never replays input.

The platform calls `suspend()` and `resume()`. macOS maps NSWorkspace sleep/wake to
these methods. iOS calls `suspend(disconnectTransport: true)` only on background;
inactive states save metadata without cancelling permission dialogs. No background
entitlement or indefinite SSH execution is implied. On
resume, surviving connections are checked before use; eligible tmux sessions may
reattach using the same identifiers.

## Files And Trust

`FilesModel` accepts a `ConnectionProvider`, not an SFTP implementation. Native document
pickers supply URLs; security-scoped access covers the entire async transfer. SFTP
operations translate connection loss to `TerminalConnectionError` while preserving
per-file failures such as permission denial. A transport failure marks Files offline;
the last directory listing stays in memory. File operation IDs and connection IDs
both guard progress and completion callbacks.

`ServerTrustModel` receives a `SecretStore`. Prompt presentation and system settings
remain platform concerns. Trust must remain explicit and changed keys stay blocked.

`CloudSyncModel` depends on `SyncedHostLibrary` and `HostSyncService`; push registration
is an injected closure. No NSApplication or UIApplication singleton belongs in the
shared coordinator. The host app retains the decision about active sessions and
when remote profile changes can be applied.

## Remaining Mobile Work

1. Exercise permission prompts, Keychain access groups, CloudKit account changes,
   security-scoped files and recovery on real devices. Simulator compilation does not
   verify these permissions, entitlements or system lifecycle behavior.
2. Add mobile file browsing separately if requested; do not introduce Finder services.
3. Define per-scene ownership before supporting multiple iPad windows.

Do not add platform branches to transport-independent session logic for view concerns.
Additional file protocols should implement `RemoteFileSession` and expose capabilities;
terminal availability must not be inferred from file protocol support.

## Localization

Use `L10n.text` for application-owned display text, including strings constructed in
models/errors and labels passed indirectly to SwiftUI. Resources live in
`Sources/FarportLocalization/Resources/{en,ru}.lproj/Localizable.strings`. Keep complete
sentences together, use matching `%@`/`%lld` arguments, and add both translations.
The active application/system language selects the bundle; unsupported languages fall
back to English. Restart after changing the app language in system settings.

Do not translate protocol commands, provider IDs, bundle/storage identifiers, persisted
enum raw values, server output, fingerprints, paths or user-assigned names. Existing tab
titles remain data; newly created default titles use the active language. System and
third-party errors retain their own localizedDescription; remote output is never rewritten.
Local Network usage descriptions belong in the app's localized InfoPlist.strings.

Package tests check both catalogs and placeholder parity, locale fallback, interpolation,
portable recovery, stale file callbacks, transport-vs-file errors and workspace identity.
The macOS suite separately covers native rendering/ANSI colors and UI integration.
