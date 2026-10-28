import AppKit
import FarportSessions
import SwiftTerm

final class SystemTerminalView: TerminalView {
    private var appliedAppearance: NSAppearance.Name?
    var remoteInputEnabled = false
    private var scrollInput = TerminalScrollInput()
    private var inputMonitor: Any?
    private var primaryMouseReportsRemote = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, sendControlKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func sendControlKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control), !event.modifierFlags.contains(.command),
              !hasMarkedText(),
              let bytes = TerminalKeyboardInput.controlSequence(
                characters: event.charactersIgnoringModifiers ?? "",
                fallback: Self.controlKeyFallback[event.keyCode], meta: event.modifierFlags.contains(.option)
              ) else { return false }
        if remoteInputEnabled {
            selectNone()
            send(bytes)
        }
        return true
    }

    // AppKit virtual key codes are layout-independent; preserve Latin layouts such as Dvorak via characters first.
    private static let controlKeyFallback: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 26: "7", 28: "8", 30: "]", 31: "o", 32: "u",
        33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 42: "\\", 45: "n", 46: "m", 49: " "
    ]

    private func handleInput(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, !isHiddenOrHasHiddenAncestor else { return event }
        if event.type == .keyDown {
            return window?.firstResponder === self && sendControlKey(event) ? nil : event
        }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if event.type == .scrollWheel {
            guard inside else { return event }
            handleScrollWheel(event)
            return nil
        }
        if event.type == .leftMouseDown {
            guard inside else { return event }
            window?.makeFirstResponder(self)
            primaryMouseReportsRemote = remoteInputEnabled && getTerminal().mouseMode != .off &&
                event.modifierFlags.contains(.option)
        }
        guard primaryMouseReportsRemote else { return event }
        if event.type == .leftMouseUp { primaryMouseReportsRemote = false }
        if remoteInputEnabled { reportPrimaryMouse(event) }
        return nil
    }

    private func reportPrimaryMouse(_ event: NSEvent) {
        let terminal = getTerminal()
        let release = event.type == .leftMouseUp
        let motion = event.type == .leftMouseDragged
        guard terminal.mouseMode != .off else { return }
        if release, terminal.mouseMode == .x10 { return }
        if motion, terminal.mouseMode != .buttonEventTracking, terminal.mouseMode != .anyEvent { return }
        let location = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: location.x, y: bounds.height - location.y)
        let cell = scrollCellSize
        let column = max(0, min(terminal.cols - 1, Int(point.x / cell.width)))
        let row = max(0, min(terminal.rows - 1, Int(point.y / cell.height)))
        let flags = terminal.encodeButton(button: 0, release: release,
                                          shift: event.modifierFlags.contains(.shift), meta: false,
                                          control: event.modifierFlags.contains(.control))
        if motion {
            terminal.sendMotion(buttonFlags: flags, x: column, y: row,
                                pixelX: max(1, Int(point.x) + 1), pixelY: max(1, Int(point.y) + 1))
        } else {
            terminal.sendEvent(buttonFlags: flags, x: column, y: row,
                               pixelX: max(1, Int(point.x) + 1), pixelY: max(1, Int(point.y) + 1))
        }
    }

    private func handleScrollWheel(_ event: NSEvent) {
        if event.phase == .began { scrollInput.reset() }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / scrollCellSize.height :
            event.scrollingDeltaY * 3
        let lines = scrollInput.lines(for: Double(delta))
        guard lines != 0 else { return }
        if remoteInputEnabled, getTerminal().mouseMode != .off,
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
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        primaryMouseReportsRemote = false
        allowMouseReporting = false
        guard window != nil else { return }
        // SwiftTerm's key/mouse overrides are not open. Keep interception scoped to this terminal's window/focus.
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp
        ]) { [weak self] event in
            guard let self else { return event }
            return self.handleInput(event)
        }
    }

    deinit {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
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
