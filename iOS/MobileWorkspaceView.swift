import FarportCore
import FarportLocalization
import FarportSessions
import SwiftUI
import UIKit

struct MobileWorkspaceView: View {
    @ObservedObject var workspace: SessionWorkspace<MobileTerminalModel>
    let editHost: (UUID) -> Void
    @State private var renaming = false
    @State private var title = ""
    @State private var closing = false
    @AppStorage("terminal.optionAsMeta") private var optionAsMeta = true

    var body: some View {
        VStack(spacing: 0) {
            if let terminal = workspace.terminal {
                MobileTerminalPane(model: terminal,
                                   tabTitle: workspace.tabs.first { $0.id == terminal.sessionID }?.title ?? "",
                                   editHost: editHost)
                    .id(terminal.sessionID)
            } else {
                ContentUnavailableView {
                    Label(L10n.text("No Terminals"), systemImage: "terminal")
                } actions: { Button(L10n.text("New Terminal Tab")) { workspace.addTerminal() } }
            }
        }
        .navigationTitle(workspace.host.profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(L10n.text("Terminal"), selection: $workspace.selectedTerminalID) {
                        ForEach(workspace.tabs) { tab in Text(tab.title).tag(Optional(tab.id)) }
                    }
                    Button(L10n.text("New Terminal Tab"), systemImage: "plus") { workspace.addTerminal() }
                    Button(L10n.text("Rename Tab"), systemImage: "pencil") {
                        title = workspace.tabs.first { $0.id == workspace.selectedTerminalID }?.title ?? ""
                        renaming = true
                    }.disabled(workspace.selectedTerminalID == nil)
                    Button(L10n.text("Close Tab"), systemImage: "xmark", role: .destructive) { closing = true }
                        .disabled(workspace.selectedTerminalID == nil)
                    Divider()
                    Toggle(L10n.text("Use Option as Meta"), isOn: $optionAsMeta)
                    if let terminal = workspace.terminal {
                        TerminalHistoryMenu(history: terminal.view.history, navigate: terminal.view.browseHistory)
                    }
                    Menu(L10n.text("Special Keys")) {
                        ForEach(TerminalFunctionKey.allCases) { key in
                            Button(key.rawValue) { workspace.terminal?.view.sendFunctionKey(key) }
                        }
                    }.disabled(workspace.terminal?.state != .connected)
                    Button(L10n.text("Select All")) { workspace.terminal?.view.selectAll() }
                    Button(L10n.text("Paste")) { workspace.terminal?.view.paste(nil) }
                        .disabled(workspace.terminal?.state != .connected)
                    Button(L10n.text("Copy"), systemImage: "doc.on.doc") { workspace.terminal?.view.copy(nil) }
                        .disabled(workspace.selectedTerminalID == nil)
                    Button(L10n.text("Edit Host"), systemImage: "slider.horizontal.3") {
                        editHost(workspace.host.id)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(L10n.text("Terminal Actions"))
            }
        }
        .alert(L10n.text("Rename Tab"), isPresented: $renaming) {
            TextField(L10n.text("Name"), text: $title)
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Save")) {
                if let id = workspace.selectedTerminalID { workspace.renameTerminal(id, title: title) }
            }
        }
        .confirmationDialog(L10n.text("Close Tab"), isPresented: $closing, titleVisibility: .visible) {
            Button(L10n.text("Close Tab"), role: .destructive) {
                if let id = workspace.selectedTerminalID { workspace.closeTerminal(id) }
            }
        }
    }
}

private struct MobileTerminalPane: View {
    @ObservedObject var model: MobileTerminalModel
    let tabTitle: String
    let editHost: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(tabTitle).font(.caption).foregroundStyle(.secondary)
                    Text(model.state.label).font(.subheadline)
                    if model.usesTmux { Text("tmux").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if model.state == .disconnected {
                    Button(model.connectLabel, systemImage: "bolt", action: model.connect)
                } else {
                    Button(model.disconnectLabel, systemImage: "stop", action: model.disconnect)
                }
            }.padding(.horizontal).padding(.vertical, 8)
            if let requirement = model.requirement {
                MobileConnectionRequirement(requirement: requirement, review: model.reviewRequirement)
            } else if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    if let hostID = model.settingsHostID {
                        Button(L10n.text("Host Settings"), systemImage: "slider.horizontal.3") { editHost(hostID) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.bottom, 8)
            } else if !model.endReason.isEmpty {
                Text(model.endReason).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            }
            Divider()
            MobileTerminalSurface(model: model)
                .modifier(TerminalPastePresentation(review: model.view.pasteReview, send: model.view.sendPaste))
                .modifier(TerminalHistoryPresentation(history: model.view.history, navigate: model.view.browseHistory))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.text("Keyboard"), systemImage: "keyboard") {
                    if model.view.isFirstResponder { _ = model.view.resignFirstResponder() } else { model.view.focus() }
                }.labelStyle(.iconOnly).disabled(model.state != .connected)
            }
        }
        .confirmationDialog(L10n.text("Open Link?"), isPresented: Binding(
            get: { model.linkToOpen != nil }, set: { if !$0 { model.linkToOpen = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.text("Open in Browser")) {
                if let url = model.linkToOpen { UIApplication.shared.open(url) }
                model.linkToOpen = nil
            }
        } message: { Text(model.linkToOpen?.absoluteString ?? "") }
    }
}

private struct MobileConnectionRequirement: View {
    let requirement: ConnectionRequirement
    let review: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(requirement.title, systemImage: requirement.isWarning ? "exclamationmark.shield" : "lock.shield")
                .font(.headline)
            if case .localNetwork = requirement {
                Text(L10n.text("Allow Farport in Settings > Privacy & Security > Local Network, then retry."))
                    .font(.callout)
                Button(L10n.text("Open Settings"), systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button(actionLabel, systemImage: "arrow.right", action: review)
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
    }

    private var actionLabel: String {
        if case .localNetwork = requirement { return L10n.text("Retry Connection") }
        return L10n.text("Review Fingerprint")
    }
}
