import FarportCore
import FarportLocalization
import FarportSessions
import SwiftUI

struct MobileLibraryView: View {
    @ObservedObject var model: HostLibraryModel<MobileTerminalModel>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var deleting: SavedHost?
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            List(selection: $model.selection) {
                ForEach(model.filteredHosts) { host in
                    NavigationLink(value: host.id) {
                        Label {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(host.profile.displayName)
                                    Text(host.profile.address).font(.caption).foregroundStyle(.secondary)
                                }
                                if !host.credentialsConfigured {
                                    Image(systemName: "key").foregroundStyle(.orange)
                                        .accessibilityLabel(L10n.text("Credentials required"))
                                }
                            }
                        } icon: { Image(systemName: "server.rack") }
                    }
                    .contextMenu {
                        Button(L10n.text("Edit Host"), systemImage: "pencil") { model.editor = host }
                        Button(L10n.text("Delete Host"), systemImage: "trash", role: .destructive) { deleting = host }
                    }
                    .swipeActions {
                        Button(L10n.text("Delete"), systemImage: "trash", role: .destructive) { deleting = host }
                        Button(L10n.text("Edit Host"), systemImage: "pencil") { model.editor = host }.tint(.accentColor)
                    }
                }
            }
            .overlay {
                if model.hosts.isEmpty {
                    if horizontalSizeClass == .compact {
                        EmptyHostLibraryView(cloud: model.cloud) { model.editor = SavedHost() }
                    } else {
                        ContentUnavailableView(L10n.text("No Hosts"), systemImage: "server.rack")
                    }
                } else if model.filteredHosts.isEmpty {
                    ContentUnavailableView.search(text: model.query)
                }
            }
            .searchable(text: $model.query, prompt: L10n.text("Search hosts"))
            .navigationTitle("Farport")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.text("New Host"), systemImage: "plus") { model.editor = SavedHost() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu(L10n.text("Settings"), systemImage: "gearshape") {
                        Button(L10n.text("Server Keys"), systemImage: "key") {
                            model.trust?.showKeys(hosts: model.hosts)
                        }
                        Button(L10n.text("iCloud Hosts"), systemImage: "icloud") { model.cloud?.showingSettings = true }
                            .disabled(model.cloud == nil)
                    }
                }
            }
        } detail: {
            if let workspace = model.selectedWorkspace {
                MobileWorkspaceView(workspace: workspace) { id in model.editor = model.hosts.first { $0.id == id } }
                    .id(workspace.host.id)
            } else if model.hosts.isEmpty {
                EmptyHostLibraryView(cloud: model.cloud) { model.editor = SavedHost() }
            } else {
                ContentUnavailableView(L10n.text("Select a Host"), systemImage: "terminal")
            }
        }
        .sheet(item: $model.editor) { host in HostEditor(host: host, hosts: model.hosts, save: model.save) }
        #if DEBUG
        .modifier(ScreenshotRootModifier(model: model))
        .onAppear {
            if ScreenshotSupport.requested {
                preferredCompactColumn = ScreenshotSupport.scene == .hosts ? .sidebar : .detail
            }
        }
        #endif
        .background {
            if let trust = model.trust { ServerTrustPresentation(model: trust, hosts: model.hosts) }
            if let cloud = model.cloud { CloudSyncPresentation(model: cloud) }
        }
        .alert("Farport", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L10n.text("OK"), role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog(L10n.text("Delete '%@'?", deleting?.profile.displayName ?? ""),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(L10n.text("Delete Host"), role: .destructive) {
                if let deleting { model.delete(deleting) }
                deleting = nil
            }
        }
    }
}
