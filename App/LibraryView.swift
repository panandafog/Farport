import FarportCore
import FarportLocalization
import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @State private var deleting: SavedHost?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Label("Farport", systemImage: "terminal.fill")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(model.hosts.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
                TextField(L10n.text("Search hosts"), text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                List(selection: $model.selection) {
                    Section(L10n.text("Hosts")) {
                        ForEach(model.filteredHosts) { host in
                            HStack(spacing: 10) {
                                Image(systemName: "server.rack")
                                    .font(.title3).foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host.profile.displayName).fontWeight(.medium).lineLimit(1)
                                    Text(host.profile.hostname).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if !host.credentialsConfigured {
                                    Image(systemName: "key").foregroundStyle(.orange)
                                        .help(L10n.text("Set credentials on this Mac"))
                                        .accessibilityLabel(L10n.text("Credentials required"))
                                }
                            }
                            .padding(.vertical, 6)
                            .tag(host.id)
                            .contextMenu {
                                Button(L10n.text("Edit Host"), systemImage: "pencil") { model.editor = host }
                                Button(L10n.text("Delete Host"), systemImage: "trash", role: .destructive) {
                                    deleting = host
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                if let cloud = model.cloud { CloudSyncStatus(model: cloud) }
                HStack {
                    Button { model.editor = SavedHost() } label: { Label(L10n.text("New Host"), systemImage: "plus") }
                        .buttonStyle(.borderless)
                    Spacer()
                }.padding(14)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 320)
        } detail: {
            if let workspace = model.selectedWorkspace {
                WorkspaceView(model: workspace, finder: model.finder, hosts: model.hosts,
                              edit: { model.editor = workspace.host },
                              editConnectionHost: { id in model.editor = model.hosts.first { $0.id == id } })
                    .id(ObjectIdentifier(workspace))
            } else if model.hosts.isEmpty {
                EmptyHostLibraryView(cloud: model.cloud) { model.editor = SavedHost() }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "terminal").font(.system(size: 46, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.text("Select a host"))
                        .font(.title2.weight(.medium))
                    Button(L10n.text("Add Host"), systemImage: "plus") { model.editor = SavedHost() }
                        .buttonStyle(.borderedProminent).tint(.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Farport")
        .background {
            if let trust = model.trust { ServerTrustPresentation(model: trust, hosts: model.hosts) }
        }
        .sheet(item: $model.editor) { host in
            HostEditor(host: host, hosts: model.hosts, save: model.save)
        }
        .background {
            if let cloud = model.cloud { CloudSyncPresentation(model: cloud) }
        }
        .alert("Farport", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button(L10n.text("OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog(L10n.text("Delete '%@'?", deleting?.profile.displayName ?? ""),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(L10n.text("Delete Host"), role: .destructive) {
                if let host = deleting { model.delete(host) }
                deleting = nil
            }
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    let finder: FinderModel?
    let hosts: [SavedHost]
    let edit: () -> Void
    let editConnectionHost: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.host.profile.displayName).font(.title2.weight(.semibold)).lineLimit(1)
                    Text(model.host.profile.address).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                    if let route = model.routeSummary {
                        Label(route, systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).help(route)
                    }
                }
                Spacer(minLength: 12)
                Picker(L10n.text("Workspace"), selection: $model.mode) {
                    Label(L10n.text("Terminal"), systemImage: "terminal").tag(WorkspaceModel.Mode.terminal)
                    Label(L10n.text("Files"), systemImage: "folder").tag(WorkspaceModel.Mode.files)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                if let finder {
                    FinderControls(model: finder, host: model.host, hosts: hosts, currentFolder: model.files.path)
                }
                Button(action: edit) { Image(systemName: "slider.horizontal.3") }
                    .help(L10n.text("Edit host")).accessibilityLabel(L10n.text("Edit host"))
            }
            .padding(20)
            Divider()
            switch model.mode {
            case .terminal:
                TerminalTabs(model: model)
                if let terminal = model.terminal {
                    TerminalPane(model: terminal, editHost: editConnectionHost)
                } else {
                    ContentUnavailableView {
                        Label(L10n.text("No terminal tabs"), systemImage: "terminal")
                    } actions: {
                        Button(L10n.text("New Terminal"), systemImage: "plus") { model.addTerminal() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .files: FilesPane(model: model.files, editHost: editConnectionHost)
            }
        }
    }
}

struct TerminalPane: View {
    @ObservedObject var model: TerminalModel
    let editHost: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if model.state == .waitingForAccess {
                    ProgressView().controlSize(.small).frame(width: 14, height: 14)
                } else {
                    Image(systemName: model.state == .disconnected ? "bolt.slash.fill" : "circle.fill")
                        .foregroundStyle(statusColor).font(.caption).frame(width: 14, height: 14)
                }
                Text(model.requirement?.title ?? model.state.label)
                    .font(.callout.weight(.medium)).foregroundStyle(statusColor)
                if model.usesTmux {
                    Label("tmux", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.secondary).help(model.sessionLabel)
                }
                if model.state == .connected {
                    Text(model.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if model.state == .reconnecting {
                    Text("\(model.retryAttempt)/\(model.maximumRetries)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if let nextRetry = model.nextRetryAt {
                        Text(nextRetry, style: .timer).font(.caption).monospacedDigit()
                    }
                }
                Spacer()
                TerminalHistoryMenu(history: model.view.history, navigate: model.view.navigateHistory)
                if model.requirement != nil {
                    Button(L10n.text("Cancel"), systemImage: "xmark", action: model.disconnect)
                } else if model.state == .disconnected {
                    Button(model.connectLabel, systemImage: "bolt.fill") { model.connect() }
                        .tint(.accentColor).buttonStyle(.borderedProminent)
                } else {
                    Button(model.state == .connected ? model.disconnectLabel : L10n.text("Cancel"),
                           systemImage: "stop.fill") {
                        model.disconnect()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            if let endedAt = model.endedAt {
                HStack {
                    Text(model.endReason).fontWeight(.medium)
                    Spacer()
                    Text(endedAt, style: .time).monospacedDigit()
                }
                .font(.callout).foregroundStyle(statusColor)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(statusColor.opacity(0.08))
                .accessibilityElement(children: .combine)
            }
            if let error = model.error {
                ErrorStrip(message: error, dismiss: { model.error = nil }, settingsHostID: model.settingsHostID,
                           editHost: editHost)
            }
            if let requirement = model.requirement {
                ConnectionRequirementView(requirement: requirement, review: model.reviewRequirement)
            } else if model.state == .waitingForAccess {
                ConnectionRequirementView(requirement: .localNetwork, review: {}, waiting: true)
            }
            TerminalSurface(model: model)
                .modifier(TerminalPastePresentation(review: model.view.pasteReview, send: model.view.sendPaste))
                .modifier(TerminalHistoryPresentation(history: model.view.history,
                                                      navigate: model.view.navigateHistory))
                .id(ObjectIdentifier(model))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var statusColor: Color {
        if let requirement = model.requirement { return requirement.isWarning ? .red : .accentColor }
        return switch model.state {
        case .connected: .green
        case .connecting, .reconnecting, .checking, .suspended, .waitingForAccess: .orange
        case .disconnected: model.endedAt == nil ? .secondary : .red
        }
    }
}

struct ErrorStrip: View {
    let message: String
    let dismiss: () -> Void
    var settingsHostID: UUID?
    var editHost: ((UUID) -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.callout).textSelection(.enabled)
                if let settingsHostID, let editHost {
                    Button(L10n.text("Host Settings"), systemImage: "slider.horizontal.3") {
                        editHost(settingsHostID)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help(L10n.text("Dismiss error"))
        }
        .padding(12).background(Color.red.opacity(0.07))
    }
}
