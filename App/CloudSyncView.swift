import FarportCore
import SwiftUI

struct CloudSyncPresentation: View {
    @ObservedObject var model: CloudSyncModel
    var body: some View {
        Color.clear.frame(width: 0, height: 0).sheet(isPresented: $model.showingSettings) {
            CloudSyncView(model: model)
        }
    }
}

struct CloudSyncStatus: View {
    @ObservedObject var model: CloudSyncModel
    var body: some View {
        Button { model.showingSettings = true } label: {
            HStack {
                Image(systemName: model.pendingChanges ? "icloud.and.arrow.down" : "icloud")
                Text(model.pendingChanges ? "iCloud Updates" : model.snapshot.enabled ? "iCloud Hosts" : "iCloud Off")
                Spacer()
            }
        }.buttonStyle(.borderless).padding(.horizontal, 14).padding(.top, 10)
    }
}

struct CloudSyncView: View {
    @ObservedObject var model: CloudSyncModel
    @State private var enabling = false
    @State private var applying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("iCloud Hosts", systemImage: "icloud").font(.title2)
            Toggle("Sync host profiles", isOn: Binding(get: { model.snapshot.enabled }, set: {
                if $0 { enabling = true } else { model.setEnabled(false) }
            })).disabled(model.busy || !model.available)
            LabeledContent("Status", value: model.snapshot.status)
            LabeledContent("Queued changes", value: String(model.snapshot.pendingCount))
            if let date = model.snapshot.lastContact { LabeledContent("Last contact") { Text(date, style: .time) } }
            if model.pendingChanges {
                HStack {
                    Label("Host updates available", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Button("Apply Changes") { applying = true }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if !model.snapshot.conflicts.isEmpty {
                Text("Recovered Versions").font(.headline)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.snapshot.conflicts) { conflict in
                            HStack {
                                Text(conflict.profile?.displayName ?? "Host").lineLimit(2)
                                Spacer()
                                Button("Restore Copy", systemImage: "arrow.uturn.backward") { model.restore(conflict) }
                                Button { model.dismissConflict(conflict) } label: { Image(systemName: "xmark") }
                                    .help("Dismiss recovered version").accessibilityLabel("Dismiss recovered version")
                            }
                        }
                    }
                }.frame(maxHeight: 150)
            }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Button("Sync Now", systemImage: "arrow.clockwise", action: model.refresh)
                    .disabled(!model.snapshot.enabled || model.busy)
                Spacer()
                Button("Done") { model.showingSettings = false }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 590)
        .confirmationDialog("Sync host profiles with your current iCloud account?", isPresented: $enabling,
                            titleVisibility: .visible) {
            Button("Enable iCloud Sync") { model.setEnabled(true) }
        } message: {
            Text("Hostnames, usernames, notes and ProxyJump routes will be merged with this account. " +
                 "Passwords, private keys, server trust, Finder locations and terminal history stay on this device.")
        }
        .confirmationDialog("Apply iCloud host changes?", isPresented: $applying, titleVisibility: .visible) {
            Button("Apply Changes") { model.applyChanges() }
        } message: {
            Text("Affected connections and Finder locations will disconnect. Updated terminal tabs keep their " +
                 "buffers; deleted hosts close their tabs. Changed endpoints require credentials to be reviewed.")
        }
    }
}
