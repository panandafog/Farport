# Shared Architecture

Farport currently ships a macOS app. Its reusable Swift package targets macOS 15 and
iOS/iPadOS 17. `Scripts/verify-ios.sh` compiles Sessions, SSH and Security against the
iOS Simulator SDK, including their Core, Cloud and Localization dependencies. This
is a compile check, not an iOS app or a device/background-network test.

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

`App/LibraryEnvironment.swift` assembles the real macOS repositories and services.
`LibraryModel` coordinates the host library with macOS Finder revocation. The future
iOS composition should use the shared models, without instantiating Finder services.

## Terminal And Lifecycle

`TerminalSessionModel` owns connections, attempt generations, input gating, heartbeat,
retry budget and trust/access requirements. `TerminalOutput` accepts bytes, cursor
visibility and focus requests. It never resets the screen. macOS `TerminalModel` is
a thin SwiftTerm/AppKit adapter; an iOS renderer can implement the same output contract.

`SessionWorkspace<Terminal>` receives a terminal factory. It keeps per-tab controller
identity, so switching views does not rebuild the native terminal or lose scrollback.
Restoration retains metadata/UUIDs, stays disconnected and never replays input.

The platform calls `suspend()` and `resume()`. macOS maps NSWorkspace sleep/wake to
these methods. The iOS app must decide how scene/background events map to suspension
and cleanup; no background entitlement or indefinite SSH execution is implied. On
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

## Adding iOS

1. Add an iOS app target and composition with the existing storage/security identities
   where provisioning allows them; define explicit migration if new locations are needed.
2. Implement UIKit/SwiftTerm output, clipboard, keyboard/accessory keys and document pickers.
3. Build adaptive host/workspace screens using the shared session models; map scene
   lifecycle and push registration to their injected interfaces.
4. Exercise permission prompts, Keychain access groups, CloudKit account changes,
   security-scoped files and recovery on real devices. Simulator compilation does not
   verify these permissions, entitlements or system lifecycle behavior.

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
