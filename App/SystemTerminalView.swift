import AppKit
import FarportSessions
import SwiftTerm

final class SystemTerminalView: TerminalView {
    private var appliedAppearance: NSAppearance.Name?
    var remoteInputEnabled = false
    private var scrollInput = TerminalScrollInput()
    private var scrollMonitor: Any?

    private func handleScrollWheel(_ event: NSEvent) {
        if event.phase == .began { scrollInput.reset() }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / scrollCellSize.height :
            event.scrollingDeltaY * 3
        let lines = scrollInput.lines(for: Double(delta))
        guard lines != 0 else { return }
        if remoteInputEnabled, allowMouseReporting, getTerminal().mouseMode != .off,
           !event.modifierFlags.contains(.shift) {
            let location = convert(event.locationInWindow, from: nil)
            reportScrollWheel(lines: lines, at: CGPoint(x: location.x, y: bounds.height - location.y),
                              meta: event.modifierFlags.contains(.option),
                              control: event.modifierFlags.contains(.control))
        } else if lines > 0 {
            scrollUp(lines: lines)
        } else {
            scrollDown(lines: -lines)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySystemTheme()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applySystemTheme()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        guard window != nil else { return }
        // SwiftTerm's scrollWheel implementation is not open. Intercept only this visible terminal's events.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  !self.isHiddenOrHasHiddenAncestor,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            self.handleScrollWheel(event)
            return nil
        }
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    func applySystemTheme() {
        guard terminal != nil else { return }
        let appearance = effectiveAppearance
        guard appliedAppearance != appearance.name else { return }
        appliedAppearance = appearance.name
        let palette = TerminalPalette(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        appearance.performAsCurrentDrawingAppearance {
            // Resolve dynamic AppKit colors before SwiftTerm converts them to RGB values.
            nativeBackgroundColor = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .textBackgroundColor
            nativeForegroundColor = NSColor.textColor.usingColorSpace(.sRGB) ?? .textColor
            caretColor = nativeForegroundColor
            caretTextColor = nativeBackgroundColor
            selectedTextBackgroundColor = palette.selection
            installColors(palette.ansi)
            layer?.backgroundColor = nativeBackgroundColor.cgColor
        }
        needsDisplay = true
    }
}
