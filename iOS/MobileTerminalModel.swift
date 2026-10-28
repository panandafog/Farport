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
    func scrolled(source: TerminalView, position: Double) {}
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
    private var darkAppearance: Bool?
    private(set) var remoteInputEnabled = false
    private var scrollInput = TerminalScrollInput()
    private var lastPanTranslation: CGFloat = 0
    private var panReportsRemote = false
    private var correctingScrollOffset = false

    private var reportsRemoteScroll: Bool {
        remoteInputEnabled && allowMouseReporting && getTerminal().mouseMode != .off && !selectionActive
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 600),
                   font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular))
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        delegate = self
        panGestureRecognizer.addTarget(self, action: #selector(scrollPan(_:)))
        getTerminal().changeHistorySize(TerminalScrollInput.historyLimit)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MobileTerminalView, _: UITraitCollection) in
            view.applySystemTheme()
        }
        applySystemTheme()
    }

    required init?(coder: NSCoder) { return nil }

    override func insertText(_ text: String) {
        let accessory = inputAccessoryView as? TerminalAccessory
        guard controlModifier || accessory?.controlModifier == true, markedTextRange == nil,
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
        guard reportsRemoteScroll, !correctingScrollOffset else { return }
        let bottom = max(0, contentSize.height - bounds.height)
        guard contentOffset.y != bottom else { return }
        correctingScrollOffset = true
        contentOffset = CGPoint(x: 0, y: bottom)
        correctingScrollOffset = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySystemTheme()
    }

    func applySystemTheme() {
        let dark = traitCollection.userInterfaceStyle == .dark
        guard darkAppearance != dark else { return }
        darkAppearance = dark
        let palette = TerminalPalette(dark: dark)
        nativeBackgroundColor = UIColor.systemBackground.resolvedColor(with: traitCollection)
        nativeForegroundColor = UIColor.label.resolvedColor(with: traitCollection)
        caretColor = nativeForegroundColor
        caretTextColor = nativeBackgroundColor
        selectedTextBackgroundColor = palette.selection
        installColors(palette.ansi)
        backgroundColor = nativeBackgroundColor
        setNeedsDisplay()
    }

    func write(_ data: Data) {
        let previousOffset = contentOffset.y
        let bottom = max(0, contentSize.height - bounds.height)
        let readingHistory = !getTerminal().isCurrentBufferAlternate && previousOffset < bottom - 0.5
        feed(byteArray: Array(data)[...])
        if readingHistory, !getTerminal().isCurrentBufferAlternate {
            contentOffset.y = max(0, min(previousOffset, contentSize.height - bounds.height))
        }
    }
    func setCursorVisible(_ visible: Bool) {
        remoteInputEnabled = visible
        if !visible { panReportsRemote = false; scrollInput.reset() }
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
        _ = terminalView.resignFirstResponder()
        terminalView.removeFromSuperview()
    }

    override var keyCommands: [UIKeyCommand]? { (super.keyCommands ?? []) + controlCommands }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(sendControlCommand(_:)) {
            return terminalView.superview === viewIfLoaded && terminalView.isFirstResponder &&
                terminalView.markedTextRange == nil
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func sendControlCommand(_ command: UIKeyCommand) {
        guard terminalView.superview === viewIfLoaded, terminalView.isFirstResponder, terminalView.remoteInputEnabled,
              let bytes = TerminalKeyboardInput.controlSequence(characters: command.input ?? "",
                                                                meta: command.modifierFlags.contains(.alternate)) else {
            return
        }
        terminalView.selectNone()
        terminalView.send(bytes)
    }
}

struct MobileTerminalSurface: UIViewControllerRepresentable {
    let model: MobileTerminalModel
    func makeUIViewController(context: Context) -> UIViewController {
        MobileTerminalController(terminalView: model.view)
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
        (controller as? MobileTerminalController)?.detachTerminalView()
    }
}
