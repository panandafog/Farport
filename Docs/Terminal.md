# Terminal Improvements

The terminal improvements update the native SwiftTerm adapters, without changing SSH,
tmux session identities, workspace persistence, or iCloud payloads. The functional
roadmap is: dependency/adapters, keyboard input, selection/paste, history navigation,
search, then tab actions and recovery. Stages 1–4 (through history navigation) are
implemented. Search and on-disk transcripts remain future work.

## SwiftTerm Upgrade

Both apps use exact SwiftTerm 1.19.0, upgraded from 1.10.1. Keep project.yml and
the Xcode Package.resolved consistent; the root package does not depend on SwiftTerm.
1.19.0 is the stable release before the 1.20 pre-release and 1.99 API transition.
Release notes: https://github.com/migueldeicaza/SwiftTerm/releases/tag/v1.19.0.

The package now includes a build-tool plugin generating SwiftTerm version metadata
and Metal shader resources. Run `sh Scripts/prepare-terminal-build.sh` once to
ensure Apple's Metal Toolchain is installed for the selected Xcode. The iOS
verification script and macOS CI do this automatically. Enable
SwiftTermBuildInfoPlugin in Xcode's package-trust dialog for ordinary IDE builds.
Headless CLI builds use `-skipPackagePluginValidation` for the reviewed package;
this skips the interactive plugin approval, not its execution sandbox. Keep the
exact dependency pin and strict resolved-version checks when using that flag.
No global Xcode trust settings are changed by the repository scripts.

- macOS uses public mouseDown/mouseDragged/mouseUp overrides. Ordinary dragging
  remains local selection, including in tmux; Option-drag reports remote gestures.
  Do not add primary mouse events back to the window event monitor.
- keyDown and scrollWheel are still non-open upstream. Their existing scoped
  monitor remains until a supported API can preserve our input/scrolling policy.
- Legacy Ctrl encoding and Russian-layout fallbacks apply only when the terminal
  has not negotiated Kitty keyboard enhancements. SwiftTerm owns negotiated
  keyboard events on both platforms, including software input on iOS.
- History remains bounded to 10,000 lines, configured through the view's public
  changeScrollback API so engine, scroller and display state are updated together.
- Retained terminal instances, light/dark ANSI palettes, cursor/input gating and
  the separate iOS controller containers remain in place. No engine fork or new
  rendering backend is introduced.

## Keyboard, Selection And Paste

The Terminal menu on macOS and Terminal Actions on iOS expose the per-device
"Use Option as Meta" preference. Hardware special keys and IME remain handled by
SwiftTerm; legacy Ctrl/Russian-layout fallbacks respect the Option preference.
The mobile accessory already provides Esc, Tab, Ctrl and arrows. The Special Keys
menu additionally exposes Home/End, Page Up/Down and F1-F12. Synthetic function
keys respect application-cursor mode and emit Kitty release events when requested.

Native selection handles word/line clicks, Shift extension and soft-wrapped lines.
macOS has Copy/Paste/Select All in its context menu. Mobile pointer/touch selection
is local even in tmux, while the scroll gesture can still report remote wheel input.
The mobile actions menu also exposes Paste and Select All.

Both platforms snapshot clipboard text before sending it. CRLF/CR are normalized,
terminal control characters (including ESC and C1 controls) are removed, and any
line break, including a trailing one, requires review in a selectable preview.
Confirmation sends that snapshot once, using the server's current bracketed-paste
mode. Disconnect, tab detachment, cancellation or replacement invalidates the
pending request. No offline input is queued. Clipboard reads occur only on Paste.
Remote OSC 52 clipboard writes are ignored on both platforms; native user Copy
still works, including with disconnected sessions.

## History Navigation

The Local History menu offers Oldest Output, Previous/Next Page and Jump to Bottom.
On macOS it sits in the terminal status bar; on iOS it is in Terminal Actions.
macOS also supports Shift-Home/End and Shift-Page Up/Down while the terminal has
keyboard focus. These are local navigation commands and never send remote keys.
Unmodified hardware keys and the mobile Special Keys menu still address the server.

While reading history, a Jump to Bottom button returns to live output. Incoming
output changes its label without pulling the viewport down. History state belongs
to each retained terminal, survives disconnect/tab changes, and does not sync.
Publication is coalesced outside native layout callbacks to avoid SwiftUI update cycles.

SwiftTerm owns following, frozen viewport rows, resize/reflow, and trimming at the
10,000-line cap. Do not restore pre-feed pixel offsets or row indices: trimming
changes those indices, and iOS updates content geometry asynchronously. Once the
text being read is evicted from the bounded buffer, the earliest retained text is
the limit. We do not preserve an unbounded transcript in memory or on disk.

Remote mouse-wheel reports remain separate from local history: macOS Shift-wheel
always scrolls locally, as does ordinary wheel input while already browsing history.
On mobile, choosing Local History switches gestures to local scrolling until the
user returns to the bottom. At the live screen, mouse-enabled tmux still receives
wheel gestures. Alternate-screen programs expose no local scrollback; local history
controls disable there, rather than silently sending Page Up/Down to the program.
This does not retrieve server-side tmux scrollback into the local buffer.

## Appearance Settings

macOS Settings (also Terminal → Terminal Appearance) and the mobile Terminal Actions
menu expose device-local preferences for following system appearance or choosing
fixed light/dark colors. Standard uses native background/text and the system accent
for the cursor and selection. Ocean and Paper provide cool and warm alternatives
with both light/dark variants. ANSI color roles retain the readable light/dark
palette; indices 16–255 and explicit RGB colors are unchanged. Settings apply to
retained terminal views without resetting buffers, selection or connection state.
Manual checks: switch each scheme/mode while output streams and text is selected;
change macOS accent while Standard is active; switch tabs and restart to check persistence.

## Build Verification

Build both apps with `-onlyUsePackageVersionsFromResolvedFile` and
`-skipPackagePluginValidation`. Compile existing app test
targets using build-for-testing without launching them. Run the package fixture
suite for SSH/tmux recovery and keyboard-byte encoding. Dependency engine tests
can exercise HistoryTests, ScreenTests, ReflowTests, BufferTests,
KittyKeyboardEncoderTests, KittyKeyboardProtocolTests and UnicodeTests without
creating terminal views or launching an app.

Interactive verification is manual; compilation and headless tests cannot prove
gesture routing, keyboard responder behavior or rendering on a physical device.
Use disposable local connections for these checks:

1. Produce long output, scroll up, and keep reading while more output arrives.
2. Select/copy in a normal shell and in mouse-enabled tmux. Confirm Option-drag
   reports remote input on macOS while an ordinary drag still selects locally.
3. Switch tabs/hosts and change system appearance. Output and selection should
   remain; a theme change must not recreate the terminal or send input.
4. Disconnect/reconnect or detach/reattach tmux. Retain local history, reject
   offline input, and reattach the same server session without replaying commands.
5. Check Ctrl-C/Ctrl-U with Latin and Russian layouts, normal Command copy/paste,
   and a program negotiating Kitty keyboard input.
6. On iPhone/iPad, switch tabs, rotate, and show/hide the keyboard. Check retained
   buffers, touch scrolling, selection, and hardware Ctrl keys.
7. Toggle Option/Meta, restart, and verify the saved choice with an international
   keyboard layout. Test Home/End, Page Up/Down and F1-F12 in shell, less and vim.
8. Copy a command wrapped by window width and confirm that no extra newline is
   inserted. Test word/line selection, Shift extension and the context menu on Mac.
9. Paste a single line, a line ending in CR/LF, and several lines. Review/cancel,
   then disconnect during review and ensure stale confirmation sends nothing.
   Repeat with bracketed-paste mode enabled and disabled on the remote side.
10. Navigate local history using the menu, Mac Shift-navigation keys and the return
    button; repeat after disconnect. Check the new-output label while streaming.
11. Produce more than 10,000 lines while reading older retained text. Verify it
    stays anchored until evicted; resize/rotate and show/hide the mobile keyboard.
12. Check local history versus mouse-enabled tmux scrolling, then enter/exit vim
    or less. Local navigation must not accidentally send remote key sequences.
13. Emit OSC 52 from a disposable server and confirm it cannot replace the clipboard;
    normal Copy/Select All must still work.


## Experimental smooth scrolling (demo/smooth-terminal-scroll)

macOS trackpad and other precise wheel events move local scrollback by points,
including AppKit momentum. Ordinary wheel notches remain line-based. The demo uses
vendored SwiftTerm 1.19.0; see `Vendor/SwiftTerm/UPSTREAM.md` for the patch scope.
The CoreGraphics renderer draws the extra partial row and adjusts selection/link
hit testing, IME positions and the caret. Metal is disabled when smooth scrolling
starts. iOS rendering remains upstream.

Fractional position is transient: integer history navigation, resize and window
reattachment discard it. Existing integer engine scrollback anchoring is retained;
this does not add transcript or scroll-position persistence across app restarts.
Remote mouse reporting (including tmux copy mode) remains discrete. Hold Shift to
scroll local history instead. For a useful manual comparison, use a plain SSH tab
or Shift-scroll after producing several hundred numbered lines.

Manual checks: slowly reverse direction within a row; coast to both history edges;
select/copy across partial rows; inspect ANSI backgrounds, wide characters and
links; receive output while scrolled up; resize and switch tabs; jump to latest;
check tmux wheel versus Shift-wheel. UI checks are left to the user. Arithmetic
regressions run with `swift test --package-path Vendor/SwiftTerm --filter
FractionalScrollPositionTests`.
