import FarportSessions
import SwiftUI

struct MobileAppRoot: View {
    let loadLibrary: () -> HostLibraryModel<MobileTerminalModel>
    let didLoad: (HostLibraryModel<MobileTerminalModel>) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: HostLibraryModel<MobileTerminalModel>?

    var body: some View {
        Group {
            if let model {
                MobileLibraryView(model: model)
            } else {
                ProgressView().accessibilityLabel("Farport")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard model == nil else { return }
            // Restoring hosts constructs UIKit terminals. Do this outside SwiftUI's initial body evaluation.
            let loaded = loadLibrary()
            model = loaded
            didLoad(loaded)
            if scenePhase == .background { loaded.suspend(disconnectTransport: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model?.resume()
                model?.cloud?.refresh()
            case .background: model?.suspend(disconnectTransport: true)
            case .inactive: model?.persistWorkspace()
            @unknown default: break
            }
        }
    }
}
