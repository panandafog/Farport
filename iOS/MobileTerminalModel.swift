import FarportCore
import FarportSessions
import SwiftTerm
import SwiftUI
import UIKit

@MainActor
final class MobileTerminalModel: TerminalSessionModel {
    let view: MobileTerminalView
    @Published var linkToOpen: URL?

    init(host: SavedHost, provider: any ConnectionProvider, sessionID: UUID, trust: ServerTrustModel?) {
        view = MobileTerminalView()
        super.init(host: host, provider: provider, sessionID: sessionID, trust: trust, output: view)
        view.terminalDelegate = self
    }
}

extension MobileTerminalModel: @preconcurrency TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) { send(Data(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        resize(TerminalSize(columns: newCols, rows: newRows))
    }
    func setTerminalTitle(source: TerminalView, title: String) { updateTitle(title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) { view.updateHistory(view.history) }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return }
        linkToOpen = url
    }
    func clipboardCopy(source: TerminalView, content: Data) {
        // Remote OSC 52 must not overwrite the system clipboard without a user action.
    }
}

final class MobileTerminalView: TerminalView, TerminalOutput {
    let pasteReview = TerminalPasteReview()
    let history = TerminalHistoryState()

    override func paste(_ sender: Any?) {
        guard remoteInputEnabled, let text = UIPasteboard.general.string,
              let immediate = pasteReview.prepare(text) else { return }
        sendPaste(immediate)
    }

    func sendPaste(_ text: String) {
        guard remoteInputEnabled else { return }
        selectNone()
        send(TerminalPasteReview.bytes(text, bracketed: getTerminal().bracketedPasteMode))
    }

    func sendFunctionKey(_ key: TerminalFunctionKey) {
        guard remoteInputEnabled else { return }
        let terminal = getTerminal()
        selectNone()
        let enhanced = !terminal.keyboardEnhancementFlags.isEmpty
        var bytes = key.bytes(applicationCursor: terminal.applicationCursor, enhanced: enhanced)
        if terminal.keyboardEnhancementFlags.contains(.reportEvents) {
            bytes += key.bytes(applicationCursor: terminal.applicationCursor, enhanced: enhanced, release: true)
        }
        send(bytes)
    }
    private var appliedPalette: TerminalResolvedPalette?
    var theme = TerminalAppearance() { didSet { if readyForHistoryUpdates { applySystemTheme() } } }
    private(set) var remoteInputEnabled = false
    private var scrollInput = TerminalScrollInput()
    private var lastPanTranslation: CGFloat = 0
    private var panReportsRemote = false
    private var correctingScrollOffset = false
    private var localHistoryNavigation = false
    private var readyForHistoryUpdates = false

    private var reportsRemoteScroll: Bool {
        remoteInputEnabled && getTerminal().mouseMode != .off && !selectionActive && !localHistoryNavigation
    }

    func browseHistory(_ action: TerminalHistoryAction) {
        guard canScroll else { return }
        localHistoryNavigation = true
        panReportsRemote = false
        navigateHistory(action)
        localHistoryNavigation = isReadingLocalHistory
        updateHistory(history)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate, !isReadingLocalHistory { localHistoryNavigation = false }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if !isReadingLocalHistory { localHistoryNavigation = false }
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 600),
                   font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular))
        readyForHistoryUpdates = true
        keyboardDismissMode = .interactive
        allowMouseReporting = false
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        delegate = self
        panGestureRecognizer.addTarget(self, action: #selector(scrollPan(_:)))
        changeScrollback(TerminalScrollInput.historyLimit)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MobileTerminalView, _: UITraitCollection) in
            view.applySystemTheme()
        }
        applySystemTheme()
    }

    required init?(coder: NSCoder) { return nil }

    override func insertText(_ text: String) {
        let accessory = inputAccessoryView as? TerminalAccessory
        guard getTerminal().keyboardEnhancementFlags.isEmpty,
              controlModifier || accessory?.controlModifier == true, markedTextRange == nil,
              let bytes = TerminalKeyboardInput.controlSequence(characters: text, meta: metaModifier) else {
            super.insertText(text)
            return
        }
        controlModifier = false
        accessory?.controlModifier = false
        metaModifier = false
        if remoteInputEnabled {
            selectNone()
            send(bytes)
        }
    }

    override func mouseModeChanged(source: Terminal) {
        // Keep the native scroll pan: upstream replaces it with a mouse-drag gesture for tmux.
        scrollInput.reset()
        if source.mouseMode == .off { super.mouseModeChanged(source: source) }
    }

    @objc private func scrollPan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            scrollInput.reset()
            lastPanTranslation = 0
            panReportsRemote = reportsRemoteScroll
        }
        guard panReportsRemote, reportsRemoteScroll, gesture.state == .changed else { return }
        let translation = gesture.translation(in: self).y
        let delta = translation - lastPanTranslation
        lastPanTranslation = translation
        let lines = scrollInput.lines(for: Double(delta / scrollCellSize.height))
        let location = gesture.location(in: self)
        reportScrollWheel(lines: lines, at: CGPoint(x: location.x, y: location.y - bounds.minY))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        defer { updateHistory(history) }
        guard reportsRemoteScroll, !correctingScrollOffset else { return }
        let bottom = max(0, contentSize.height - bounds.height)
        guard contentOffset.y != bottom else { return }
        correctingScrollOffset = true
        scroll(toPosition: 1)
        contentOffset = CGPoint(x: 0, y: bottom)
        correctingScrollOffset = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySystemTheme()
        updateHistory(history)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if readyForHistoryUpdates { updateHistory(history) }
    }

    func applySystemTheme() {
        let dark = theme.usesDarkColors(systemDark: traitCollection.userInterfaceStyle == .dark)
        let traits = traitCollection.modifyingTraits { $0.userInterfaceStyle = dark ? .dark : .light }
        let standard = theme.scheme == .standard
        let palette = TerminalResolvedPalette(scheme: theme.scheme, dark: dark,
            background: standard ? UIColor.systemBackground.resolvedColor(with: traits) :
                TerminalResolvedPalette.color(theme.scheme.background(dark: dark)),
            foreground: standard ? UIColor.label.resolvedColor(with: traits) :
                TerminalResolvedPalette.color(theme.scheme.foreground(dark: dark)),
            accent: standard ? tintColor.resolvedColor(with: traits) :
                TerminalResolvedPalette.color(theme.scheme.accent(dark: dark)))
        guard appliedPalette != palette else { return }
        appliedPalette = palette
        installTheme(palette)
        backgroundColor = nativeBackgroundColor
        setNeedsDisplay()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        if readyForHistoryUpdates { applySystemTheme() }
    }

    func write(_ data: Data) {
        feed(byteArray: Array(data)[...])
        if !canScroll { localHistoryNavigation = false }
        updateHistory(history, receivedOutput: !data.isEmpty)
    }
    func setCursorVisible(_ visible: Bool) {
        remoteInputEnabled = visible
        if !visible { panReportsRemote = false; scrollInput.reset(); pasteReview.cancel() }
        if visible { getTerminal().showCursor() } else {
            getTerminal().hideCursor()
            _ = resignFirstResponder()
        }
    }
    func focus() { if window != nil { _ = becomeFirstResponder() } }
}

final class MobileTerminalController: UIViewController {
    let terminalView: MobileTerminalView
    private lazy var controlCommands: [UIKeyCommand] = {
        let modifiers: [UIKeyModifierFlags] = [.control, [.control, .shift],
                                              [.control, .alternate], [.control, .alternate, .shift]]
        return modifiers.flatMap { flags in
            TerminalKeyboardInput.shortcutCharacters.map { character in
                let command = UIKeyCommand(input: character, modifierFlags: flags,
                                           action: #selector(sendControlCommand(_:)))
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }
    }()

    init(terminalView: MobileTerminalView) {
        self.terminalView = terminalView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }
    override func loadView() {
        // SwiftUI can create a replacement controller before dismantling the previous one.
        // Only the container belongs to this controller; the model retains the terminal across mounts.
        let container = UIView(frame: CGRect(origin: .zero, size: terminalView.bounds.size))
        container.backgroundColor = .systemBackground
        view = container
        terminalView.removeFromSuperview()
        terminalView.frame = container.bounds
        terminalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(terminalView)
    }

    func detachTerminalView() {
        guard let container = viewIfLoaded, terminalView.superview === container else { return }
        terminalView.pasteReview.cancel()
        _ = terminalView.resignFirstResponder()
        terminalView.removeFromSuperview()
    }

    override var keyCommands: [UIKeyCommand]? {
        guard terminalView.getTerminal().keyboardEnhancementFlags.isEmpty else { return super.keyCommands }
        return (super.keyCommands ?? []) + controlCommands
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(sendControlCommand(_:)) {
            return terminalView.getTerminal().keyboardEnhancementFlags.isEmpty &&
                terminalView.superview === viewIfLoaded && terminalView.isFirstResponder &&
                terminalView.markedTextRange == nil
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func sendControlCommand(_ command: UIKeyCommand) {
        guard terminalView.getTerminal().keyboardEnhancementFlags.isEmpty,
              terminalView.superview === viewIfLoaded, terminalView.isFirstResponder, terminalView.remoteInputEnabled,
              let bytes = TerminalKeyboardInput.controlSequence(characters: command.input ?? "",
                                                                meta: terminalView.optionAsMetaKey &&
                                                                    command.modifierFlags.contains(.alternate)) else {
            return
        }
        terminalView.selectNone()
        terminalView.send(bytes)
    }
}

struct MobileTerminalSurface: UIViewControllerRepresentable {
    let model: MobileTerminalModel
    @AppStorage("terminal.optionAsMeta") private var optionAsMeta = true
    @TerminalAppearanceStorage private var theme
    func makeUIViewController(context: Context) -> UIViewController {
        MobileTerminalController(terminalView: model.view)
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        model.view.optionAsMetaKey = optionAsMeta
        model.view.theme = theme
    }
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
        (controller as? MobileTerminalController)?.detachTerminalView()
    }
}
