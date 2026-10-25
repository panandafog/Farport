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

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 600),
                   font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular))
        keyboardDismissMode = .interactive
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MobileTerminalView, _: UITraitCollection) in
            view.applySystemTheme()
        }
        applySystemTheme()
    }

    required init?(coder: NSCoder) { return nil }

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

    func write(_ data: Data) { feed(byteArray: Array(data)[...]) }
    func setCursorVisible(_ visible: Bool) {
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
