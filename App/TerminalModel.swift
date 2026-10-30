import AppKit
import FarportCore
import FarportSessions
import SwiftTerm
import SwiftUI

@MainActor
final class TerminalModel: TerminalSessionModel {
    let view: SystemTerminalView

    init(host: SavedHost, provider: any ConnectionProvider, policy: ConnectionRecoveryPolicy = .init(),
         sessionID: UUID? = nil, trust: ServerTrustModel? = nil) {
        view = SystemTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 540),
                                  font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        super.init(host: host, provider: provider, policy: policy, sessionID: sessionID, trust: trust, output: view)
        view.terminalDelegate = self
        view.changeScrollback(TerminalScrollInput.historyLimit)
        view.applySystemTheme()
    }
}

extension SystemTerminalView: TerminalOutput {
    func write(_ data: Data) {
        feed(byteArray: Array(data)[...])
        updateHistory(history, receivedOutput: !data.isEmpty)
    }
    func setCursorVisible(_ visible: Bool) {
        remoteInputEnabled = visible
        if !visible { pasteReview.cancel() }
        if visible { getTerminal().showCursor() } else { getTerminal().hideCursor() }
    }
    func focus() { window?.makeFirstResponder(self) }
}

extension TerminalModel: @preconcurrency TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) { send(Data(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        resize(TerminalSize(columns: newCols, rows: newRows))
    }
    func setTerminalTitle(source: TerminalView, title: String) { updateTitle(title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) { view.updateHistory(view.history) }
    func bell(source: TerminalView) { NSSound.beep() }
    func clipboardCopy(source: TerminalView, content: Data) {
        // Remote OSC 52 must not overwrite the clipboard. Native user Copy remains available.
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

struct TerminalSurface: NSViewRepresentable {
    let model: TerminalModel
    @AppStorage("terminal.optionAsMeta") private var optionAsMeta = true
    @TerminalAppearanceStorage private var theme
    func makeNSView(context: Context) -> TerminalView { model.view }
    func updateNSView(_ nsView: TerminalView, context: Context) {
        nsView.optionAsMetaKey = optionAsMeta
        model.view.theme = theme
    }
}
