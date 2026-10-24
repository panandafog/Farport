# Debugging Farport

Use the same Apple Development-signed Debug app for Finder launches, CLI builds,
and Xcode debugging. XcodeGen configures the project's shared Derived Data location
as `Build`; the normal app is `Build/Build/Products/Debug/Farport.app`.
The project, schemes, product and process are named Farport.
CLI builds must also pass `-derivedDataPath Build`; xcodebuild ignores the IDE's
Derived Data preferences. Do not override `SYMROOT`: Swift Package Manager rejects
legacy/custom build-product locations.
Project settings apply to this project only, not Xcode's global preferences.
Generation configures both shared settings and the current user's project settings,
preserving other keys. Existing per-user defaults otherwise override the shared path.

## Normal Workflow

Select the **Farport** scheme and **My Mac**, then press **Command-R**. This builds
and launches the canonical Debug app automatically under the debugger. Use this
scheme for ordinary one-button development; **Farport Attach** is a manual fallback,
not an automatic launcher.

Both schemes use the same build path. This avoids accidentally testing different
installed copies, but does not guarantee Local Network access under an Xcode launch.
If the same signed app works from Finder but remains blocked when launched by
Xcode, use the external-launch workflow below.

## Manual Attach Fallback

1. Open `Farport.xcodeproj` and select the **Farport Attach** scheme and **My Mac**.
2. When it is safe to detach existing sessions, quit the previous Farport process.
3. Set breakpoints and press **Command-R**. Xcode builds Debug and waits for launch.
4. Open `Build/Build/Products/Debug/Farport.app` in Finder, or run
   `sh Scripts/open-debug.sh` from the repository root. Xcode attaches to this app.

**Waiting to attach** is intentional in this scheme: Run does not launch the app.
If you wanted an ordinary Run, press Stop and switch back to **Farport**.

The script uses Launch Services; it does not run the executable directly under
Terminal, inherit Terminal's network exemption, or modify privacy permissions.
Avoid starting another installed copy simultaneously. Existing sessions must not
be killed automatically. Only rebuild/restart when their interruption is acceptable.
For a process already running, use **Debug > Attach to Process > Farport** instead.
For isolated UI testing, the helper accepts `--host-library /absolute/test/hosts.json`;
quit the prior process first, as opening an existing app does not replace its arguments.
All app configurations are sandboxed. A command-line path is not a user-granted file
permission: prepare a disposable library inside the app container, or grant access
through a native file panel. The fixture's external temporary path is suitable for
package tests but is not automatically accessible to a sandboxed app. Do not add
temporary filesystem exceptions or use the real host library to work around this.
First-container migration must be tested in a disposable macOS account; see [Sandbox](Sandbox.md).

Do not assume a working Finder launch proves a debugger-launched copy has access.
If Local Network remains blocked after a grant, quit and reopen the same copy.
There is no public API to reset a saved denial or force another permission dialog.

## Connection Permission Wait

For a foreground Terminal/Files connection only, a system-confirmed Local Network
failure starts a cancellable, 30-second TCP-only wait to the first route endpoint.
The UI shows that it is waiting and offers System Settings and Cancel. No SSH
credentials are sent by the wait. When Network.framework reports TCP readiness
or the probe ends with a different failure, the original operation retries once,
including all host-key checks. A second
failure or expired wait ends with a manual requirement, never a retry loop.
Cancel, host edits, tab closure and app shutdown invalidate pending work.
Automatic recovery and background File Provider operations do not use this wait.

Readiness is not a general permission-status API. A refusal, DNS failure or another
path error ends the wait with one fresh SSH attempt, so its actual error replaces
the stale permission requirement. A deadline without a new path result preserves
the original blocking requirement; a manual retry starts a fresh attempt.

## Generation And Validation

`project.yml` and `Scripts/configure-debugging.swift` are the sources of truth.
Regenerate with `sh Scripts/xcodegen.sh generate` (checksum-pinned XcodeGen 2.44.1);
do not edit the generated scheme by hand or use an unpinned system generator.
The post-generation script merges workspace settings and sets the attach scheme's
launch mode through an XML parser. **File > Project Settings** should show
**Project-relative Location**, `Build`, with the resolved path inside this repository.
After regeneration, reopen those settings or the project if Xcode still has an older
cached location. Do not change Xcode's global Derived Data directory.

Run the hosted tests with the **Farport** scheme, then run a normal build to remove
test-only signing exceptions. Verify the signed extension remains sandboxed.

References:
- https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- https://developer.apple.com/documentation/xcode/diagnosing-and-resolving-bugs-in-your-running-app

## Verified Workflow

The generated **Farport Attach** scheme was checked in Xcode: it waited for an
external launch, attached to the normal Debug app with an empty isolated library,
resolved a source breakpoint in `LibraryModel.closeAll()`, and stopped there when
the test app quit. The temporary breakpoint and process were removed afterward.
The terminal/file waiting states and late-grant cancellation are covered by hosted
tests; the full SSH/SFTP/ProxyJump/tmux suite uses a disposable loopback server.
The real first-use macOS permission dialog was not reset/retested: existing system
permissions were kept. Local Network operation against a real LAN server while
attached to Xcode still needs the user's verification.
