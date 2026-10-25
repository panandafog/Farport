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
    private var remoteInputEnabled = false
    private var scrollInput = TerminalScrollInput()
    private var lastPanTranslation: CGFloat = 0
    private var panReportsRemote = false
    private var correctingScrollOffset = false

    private var reportsRemoteScroll: Bool {
        remoteInputEnabled && allowMouseReporting && getTerminal().mouseMode != .off
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

struct MobileTerminalSurface: UIViewRepresentable {
    let model: MobileTerminalModel
    func makeUIView(context: Context) -> MobileTerminalView { model.view }
    func updateUIView(_ uiView: MobileTerminalView, context: Context) {}
    static func dismantleUIView(_ uiView: MobileTerminalView, coordinator: ()) { _ = uiView.resignFirstResponder() }
}
