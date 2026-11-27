import FarportLocalization
import FarportSessions
import SwiftUI

@MainActor
final class ShortcutHostNavigation: ObservableObject {
    static let shared = ShortcutHostNavigation()
    @Published var pendingHostID: UUID?
}

struct ShortcutHostNavigationPresentation<Terminal: TerminalSessionModel>: ViewModifier {
    @ObservedObject var model: HostLibraryModel<Terminal>
    @ObservedObject private var navigation = ShortcutHostNavigation.shared

    func body(content: Content) -> some View {
        content.onChange(of: navigation.pendingHostID) { _, _ in openPendingHost() }
            .onAppear(perform: openPendingHost)
    }

    private func openPendingHost() {
        guard let id = navigation.pendingHostID else { return }
        navigation.pendingHostID = nil
        guard model.editor == nil else {
            model.error = L10n.text("Finish editing the current host, then run Open Host Settings again.")
            return
        }
        guard let host = model.hosts.first(where: { $0.id == id }) else {
            model.error = L10n.text("This saved host no longer exists. Select another host in Shortcuts.")
            return
        }
        model.query = ""
        model.selection = id
        model.editor = host
    }
}
