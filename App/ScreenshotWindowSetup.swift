#if DEBUG
import AppKit
import SwiftUI

struct ScreenshotWindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ScreenshotWindowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ScreenshotWindowView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard ScreenshotSupport.requested, let window else { return }
        // Includes the title bar: 1280×800 at 1x, 2560×1600 at 2x, both accepted by FramePilot.
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1280, height: 800)), display: true)
        window.center()
        let prefix = "--screenshot-appearance="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) {
            let appearance = String(argument.dropFirst(prefix.count))
            if appearance == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
            if appearance == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        }
    }
}
#endif
