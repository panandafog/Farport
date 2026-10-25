import FarportLocalization
import FarportSessions
import SwiftUI

struct EmptyHostLibraryView: View {
    let cloud: CloudSyncModel?
    let addHost: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.text("No hosts yet"), systemImage: "server.rack")
        } actions: {
            VStack(spacing: 12) {
                Button(L10n.text("Add First Host"), systemImage: "plus", action: addHost)
                    .buttonStyle(.borderedProminent)
                if let cloud, cloud.available { EmptyLibraryCloudAction(model: cloud) }
            }.multilineTextAlignment(.center)
        }
    }
}

private struct EmptyLibraryCloudAction: View {
    @ObservedObject var model: CloudSyncModel
    @State private var enabling = false
    @State private var attemptedEnable = false

    var body: some View {
        VStack(spacing: 12) {
            if model.busy { ProgressView().controlSize(.small) }
            if !model.snapshot.enabled {
                Button(L10n.text("Enable iCloud Sync"), systemImage: "icloud") {
                    attemptedEnable = true
                    enabling = true
                }.buttonStyle(.bordered).disabled(model.busy)
            }
            if attemptedEnable, let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                Button(L10n.text("iCloud Hosts"), systemImage: "gearshape") { model.showingSettings = true }
            }
        }
        .modifier(CloudSyncEnableConfirmation(model: model, isPresented: $enabling))
    }
}
