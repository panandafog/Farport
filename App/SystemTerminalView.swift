import AppKit
import FarportCore
import FarportLocalization
import FarportSessions
import SwiftTerm

final class SystemTerminalView: TerminalView {
    private var appliedPalette: TerminalResolvedPalette?
    private var colorObserver: NSObjectProtocol?
    var decorationColorsChanged: ((TerminalDecorationColors) -> Void)?
    var theme = TerminalAppearance() { didSet { applySystemTheme() } }
    var remoteInputEnabled = false
    let pasteReview = TerminalPasteReview()
    let history = TerminalHistoryState()

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copy = menu.addItem(withTitle: L10n.text("Copy"), action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        let paste = menu.addItem(withTitle: L10n.text("Paste"), action: #selector(paste(_:)), keyEquivalent: "")
        paste.target = self
        let all = menu.addItem(withTitle: L10n.text("Select All"), action: #selector(selectAll(_:)), keyEquivalent: "")
        all.target = self
        return menu
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) { return remoteInputEnabled && NSPasteboard.general.canReadItem(
            withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue]) }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any) {
        guard remoteInputEnabled, let text = NSPasteboard.general.string(forType: .string),
              let immediate = pasteReview.prepare(text) else { return }
        sendPaste(immediate)
    }

    func sendPaste(_ text: String) {
        guard remoteInputEnabled else { return }
        selectNone()
        send(TerminalPasteReview.bytes(text, bracketed: getTerminal().bracketedPasteMode))
    }
    private var scrollInput = TerminalScrollInput()
    private var inputMonitor: Any?
    private var primaryMouseReportsRemote = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, sendControlKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func sendControlKey(_ event: NSEvent) -> Bool {
        guard getTerminal().keyboardEnhancementFlags.isEmpty,
              event.modifierFlags.contains(.control), !event.modifierFlags.contains(.command),
              !hasMarkedText(),
              let bytes = TerminalKeyboardInput.controlSequence(
                characters: event.charactersIgnoringModifiers ?? "",
                fallback: Self.controlKeyFallback[event.keyCode],
                meta: optionAsMetaKey && event.modifierFlags.contains(.option)
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
            if window?.firstResponder === self, navigateHistoryKey(event) { return nil }
            return window?.firstResponder === self && sendControlKey(event) ? nil : event
        }
        guard event.type == .scrollWheel, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return event
        }
        handleScrollWheel(event)
        return nil
    }

    private func navigateHistoryKey(_ event: NSEvent) -> Bool {
        guard !hasMarkedText(), event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift else {
            return false
        }
        let action: TerminalHistoryAction
        switch event.keyCode {
        case 115: action = .oldest // Shift-Home
        case 116: action = .pageUp
        case 119: action = .latest // Shift-End
        case 121: action = .pageDown
        default: return false
        }
        navigateHistory(action)
        updateHistory(history)
        return true
    }

    override func setFrameSize(_ newSize: NSSize) {
        resetSmoothScroll()
        super.setFrameSize(newSize)
        if terminal != nil { updateHistory(history) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        primaryMouseReportsRemote = remoteInputEnabled && getTerminal().mouseMode != .off &&
            event.modifierFlags.contains(.option)
        if primaryMouseReportsRemote { reportPrimaryMouse(event) } else { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if primaryMouseReportsRemote {
            if remoteInputEnabled { reportPrimaryMouse(event) }
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { primaryMouseReportsRemote = false }
        if primaryMouseReportsRemote {
            if remoteInputEnabled { reportPrimaryMouse(event) }
        } else {
            super.mouseUp(with: event)
        }
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
        if remoteInputEnabled, getTerminal().mouseMode != .off,
           !event.modifierFlags.contains(.shift), !isReadingLocalHistory {
            let lines = scrollInput.lines(for: Double(delta))
            guard lines != 0 else { return }
            let location = convert(event.locationInWindow, from: nil)
            reportScrollWheel(lines: lines, at: CGPoint(x: location.x, y: bounds.height - location.y),
                              meta: event.modifierFlags.contains(.option),
                              control: event.modifierFlags.contains(.control))
        } else if event.hasPreciseScrollingDeltas {
            scrollSmoothly(byPoints: event.scrollingDeltaY)
        } else {
            let lines = scrollInput.lines(for: Double(delta))
            guard lines != 0 else { return }
            if lines > 0 { scrollUp(lines: lines) } else { scrollDown(lines: -lines) }
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
        if let colorObserver { NotificationCenter.default.removeObserver(colorObserver) }
        colorObserver = nil
        inputMonitor = nil
        primaryMouseReportsRemote = false
        if window == nil {
            pasteReview.cancel()
            resetSmoothScroll()
        }
        allowMouseReporting = false
        guard window != nil else { return }
        colorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applySystemTheme() }
        }
        // SwiftTerm 1.19 still keeps keyDown/scrollWheel closed; pointer events use native overrides above.
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            return self.handleInput(event)
        }
    }

    deinit {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        if let colorObserver { NotificationCenter.default.removeObserver(colorObserver) }
    }

    func applySystemTheme(force: Bool = false) {
        guard terminal != nil else { return }
        let systemDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let dark = theme.usesDarkColors(systemDark: systemDark)
        let appearance = theme.followsSystem ? effectiveAppearance :
            (NSAppearance(named: dark ? .darkAqua : .aqua) ?? effectiveAppearance)
        appearance.performAsCurrentDrawingAppearance {
            let standard = theme.scheme == .standard
            let palette = TerminalResolvedPalette(scheme: theme.scheme, dark: dark,
                background: standard ? NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .white :
                    TerminalResolvedPalette.color(theme.scheme.background(dark: dark)),
                foreground: standard ? NSColor.textColor.usingColorSpace(.sRGB) ?? .black :
                    TerminalResolvedPalette.color(theme.scheme.foreground(dark: dark)),
                accent: theme.useAppAccent ? NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue :
                    TerminalResolvedPalette.color(theme.scheme.accent(dark: dark)))
            decorationColorsChanged?(palette.decorationColors(accent: NSColor.controlAccentColor,
                                                               useAppAccent: theme.useAppAccent))
            guard force || appliedPalette != palette else { return }
            appliedPalette = palette
            installTheme(palette)
            layer?.backgroundColor = nativeBackgroundColor.cgColor
        }
        needsDisplay = true
    }
}
