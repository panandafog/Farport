import FarportCore
import FarportLocalization
import FarportSessions
import SwiftUI

struct TerminalSessionModePicker: View {
    let tab: TerminalTab
    let request: (TerminalTab) -> Void

    var body: some View {
        Picker(L10n.text("Session Mode"), selection: Binding<TerminalResumeStrategy>(
            get: { tab.resumeStrategy ?? .none },
            set: { strategy in
                var candidate = tab
                candidate.resumeStrategy = strategy
                request(candidate)
            }
        )) {
            Text(L10n.text("Standard SSH")).tag(TerminalResumeStrategy.none)
            Text(L10n.text("Persistent (tmux)")).tag(TerminalResumeStrategy.tmux)
        }
    }
}

struct TerminalSessionModeConfirmation<Terminal: TerminalSessionModel>: ViewModifier {
    @ObservedObject var workspace: SessionWorkspace<Terminal>
    @Binding var candidate: TerminalTab?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            L10n.text("Change session mode?"),
            isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }),
            titleVisibility: .visible,
            presenting: candidate
        ) { tab in
            Button(L10n.text("Change Mode")) {
                if let strategy = tab.resumeStrategy { workspace.setResumeStrategy(strategy, for: tab.id) }
                candidate = nil
            }
            Button(L10n.text("Cancel"), role: .cancel) { candidate = nil }
        } message: { tab in
            Text(L10n.text("Changing mode disconnects '%@'. Reconnect to use the new mode.", tab.title) + "\n\n" +
                 L10n.text("A standard SSH shell will end. A tmux session keeps running on the server."))
        }
    }
}
