import HarborCore
import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @State private var deleting: SavedHost?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Label("Harbor", systemImage: "terminal.fill")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(model.hosts.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
                TextField("Search hosts", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                List(selection: $model.selection) {
                    Section("Hosts") {
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
                                        .help("Set credentials on this Mac").accessibilityLabel("Credentials required")
                                }
                            }
                            .padding(.vertical, 6)
                            .tag(host.id)
                            .contextMenu {
                                Button("Edit Host", systemImage: "pencil") { model.editor = host }
                                Button("Delete Host", systemImage: "trash", role: .destructive) { deleting = host }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                if let cloud = model.cloud { CloudSyncStatus(model: cloud) }
                HStack {
                    Button { model.editor = SavedHost() } label: { Label("New Host", systemImage: "plus") }
                        .buttonStyle(.borderless)
                    Spacer()
                }.padding(14)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 320)
        } detail: {
            if let workspace = model.selectedWorkspace {
                WorkspaceView(model: workspace, finder: model.finder, hosts: model.hosts,
                              edit: { model.editor = workspace.host })
                    .id(ObjectIdentifier(workspace))
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "terminal").font(.system(size: 46, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text(model.hosts.isEmpty ? "No hosts yet" : "Select a host").font(.title2.weight(.medium))
                    Button("Add Host", systemImage: "plus") { model.editor = SavedHost() }
                        .buttonStyle(.borderedProminent).tint(.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Harbor")
        .background {
            if let trust = model.trust { ServerTrustPresentation(model: trust, hosts: model.hosts) }
        }
        .sheet(item: $model.editor) { host in
            HostEditor(host: host, hosts: model.hosts, save: model.save)
        }
        .background {
            if let cloud = model.cloud { CloudSyncPresentation(model: cloud) }
        }
        .alert("Harbor", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Delete \(deleting?.profile.displayName ?? "host")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Host", role: .destructive) {
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
                Picker("Workspace", selection: $model.mode) {
                    Label("Terminal", systemImage: "terminal").tag(WorkspaceModel.Mode.terminal)
                    Label("Files", systemImage: "folder").tag(WorkspaceModel.Mode.files)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                if let finder {
                    FinderControls(model: finder, host: model.host, hosts: hosts, currentFolder: model.files.path)
                }
                Button(action: edit) { Image(systemName: "slider.horizontal.3") }
                    .help("Edit host").accessibilityLabel("Edit host")
            }
            .padding(20)
            Divider()
            switch model.mode {
            case .terminal:
                TerminalTabs(model: model)
                if let terminal = model.terminal {
                    TerminalPane(model: terminal)
                } else {
                    ContentUnavailableView {
                        Label("No terminal tabs", systemImage: "terminal")
                    } actions: {
                        Button("New Terminal", systemImage: "plus") { model.addTerminal() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .files: FilesPane(model: model.files)
            }
        }
    }
}

struct TerminalPane: View {
    @ObservedObject var model: TerminalModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if model.state == .waitingForAccess {
                    ProgressView().controlSize(.small).frame(width: 14, height: 14)
                } else {
                    Image(systemName: model.state == .disconnected ? "bolt.slash.fill" : "circle.fill")
                        .foregroundStyle(statusColor).font(.caption).frame(width: 14, height: 14)
                }
                Text(model.requirement?.title ?? model.state.rawValue)
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
                if model.requirement != nil {
                    Button("Cancel", systemImage: "xmark", action: model.disconnect)
                } else if model.state == .disconnected {
                    Button(model.connectLabel, systemImage: "bolt.fill") { model.connect() }
                        .tint(.accentColor).buttonStyle(.borderedProminent)
                } else {
                    Button(model.state == .connected ? model.disconnectLabel : "Cancel", systemImage: "stop.fill") {
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
                ErrorStrip(message: error, dismiss: { model.error = nil })
            }
            if let requirement = model.requirement {
                ConnectionRequirementView(requirement: requirement, review: model.reviewRequirement)
            } else if model.state == .waitingForAccess {
                ConnectionRequirementView(requirement: .localNetwork, review: {}, waiting: true)
            }
            TerminalSurface(model: model)
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
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(message).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss error")
        }
        .padding(12).background(Color.red.opacity(0.07))
    }
}
