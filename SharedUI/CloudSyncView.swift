import FarportCore
import FarportLocalization
import FarportSessions
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
        Button {
            model.showingSettings = true
        } label: {
            HStack {
                Image(systemName: model.pendingChanges ? "icloud.and.arrow.down" : "icloud")
                Text(statusTitle)
                Spacer()
            }
        }.buttonStyle(.borderless).padding(.horizontal, 14).padding(.top, 10)
    }

    private var statusTitle: String {
        if model.pendingChanges { return L10n.text("iCloud Updates") }
        return model.snapshot.enabled ? L10n.text("iCloud Hosts") : L10n.text("iCloud Off")
    }
}

struct CloudSyncView: View {
    @ObservedObject var model: CloudSyncModel
    @State private var enabling = false
    @State private var applying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(L10n.text("iCloud Hosts"), systemImage: "icloud").font(.title2)
                Toggle(
                    L10n.text("Sync host profiles"),
                    isOn: Binding(
                        get: { model.snapshot.enabled },
                        set: {
                            if $0 { enabling = true } else { model.setEnabled(false) }
                        })
                ).disabled(model.busy || !model.available)
                LabeledContent(L10n.text("Status"), value: model.snapshot.status)
                LabeledContent(L10n.text("Queued changes"), value: String(model.snapshot.pendingCount))
                if let date = model.snapshot.lastContact {
                    LabeledContent(L10n.text("Last contact")) { Text(date, style: .time) }
                }
                if model.pendingChanges {
                    HStack {
                        Label(L10n.text("Host updates available"), systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Button(L10n.text("Apply Changes")) { applying = true }
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if !model.snapshot.conflicts.isEmpty {
                    Text(L10n.text("Recovered Versions")).font(.headline)
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(model.snapshot.conflicts) { conflict in
                                HStack {
                                    Text(conflict.profile?.displayName ?? L10n.text("Host")).lineLimit(2)
                                    Spacer()
                                    Button(L10n.text("Restore Copy"), systemImage: "arrow.uturn.backward") {
                                        model.restore(conflict)
                                    }
                                    Button {
                                        model.dismissConflict(conflict)
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .help(L10n.text("Dismiss recovered version"))
                                    .accessibilityLabel(L10n.text("Dismiss recovered version"))
                                }
                            }
                        }
                    }.frame(maxHeight: 150)
                }
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Button(L10n.text("Sync Now"), systemImage: "arrow.clockwise", action: model.refresh)
                        .disabled(!model.snapshot.enabled || model.busy)
                    Spacer()
                    Button(L10n.text("Done")) { model.showingSettings = false }.keyboardShortcut(.cancelAction)
                }
            }.padding(24)
        }
        .sheetFrame(width: 590)
        .modifier(CloudSyncEnableConfirmation(model: model, isPresented: $enabling))
        .confirmationDialog(
            L10n.text("Apply iCloud host changes?"), isPresented: $applying,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Apply Changes")) { model.applyChanges() }
        } message: {
            #if os(iOS)
                Text(
                    L10n.text(
                        "Changed connections will disconnect. Closed tabs and deleted hosts lose local terminal "
                            + "history; other tabs keep it. Changed endpoints require credentials to be reviewed."
                    ))
            #else
                Text(
                    L10n.text(
                        "Changed connections and Finder locations will disconnect. Closed tabs and deleted hosts "
                            + "lose local terminal history; other tabs keep it. Changed endpoints require credentials "
                            + "to be reviewed."
                    ))
            #endif
        }
    }
}

struct CloudSyncEnableConfirmation: ViewModifier {
    let model: CloudSyncModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog(
            L10n.text("Sync host profiles with your current iCloud account?"), isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Enable iCloud Sync")) { model.setEnabled(true) }
        } message: {
            Text(L10n.text(
                "Hostnames, usernames, notes and ProxyJump routes will be merged with this account. "
                    + "Passwords, private keys, server trust, Finder locations and terminal history stay on "
                    + "this device."
            ))
        }
    }
}
