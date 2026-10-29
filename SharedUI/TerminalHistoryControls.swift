import FarportLocalization
import FarportSessions
import SwiftUI

struct TerminalHistoryPresentation: ViewModifier {
    @ObservedObject var history: TerminalHistoryState
    let navigate: (TerminalHistoryAction) -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if history.status.readingHistory {
                Button {
                    navigate(.latest)
                } label: {
                    Label(L10n.text(history.status.hasNewOutput ? "New Output — Jump to Bottom" : "Jump to Bottom"),
                          systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered).background(.regularMaterial, in: Capsule())
                .padding(12)
            }
        }
    }
}

struct TerminalHistoryMenu: View {
    @ObservedObject var history: TerminalHistoryState
    let navigate: (TerminalHistoryAction) -> Void

    var body: some View {
        Menu(L10n.text("Local History")) {
            Button(L10n.text("Oldest Output")) { navigate(.oldest) }
            Button(L10n.text("Previous Page")) { navigate(.pageUp) }
            Button(L10n.text("Next Page")) { navigate(.pageDown) }
            Button(L10n.text("Jump to Bottom")) { navigate(.latest) }
        }.disabled(!history.status.canScroll)
    }
}
