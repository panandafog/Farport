import HarborCore
import SwiftUI

struct FilesPane: View {
    @ObservedObject var model: FilesModel
    @State private var editingName = false
    @State private var name = ""
    @State private var renaming: RemoteEntry?
    @State private var deleting: RemoteEntry?

    var body: some View {
        VStack(spacing: 0) {
            if !model.connected {
                if let error = model.error { ErrorStrip(message: error, dismiss: { model.error = nil }) }
                if let requirement = model.requirement {
                    ConnectionRequirementView(requirement: requirement, review: model.reviewRequirement)
                } else if model.waitingForAccess {
                    ConnectionRequirementView(requirement: .localNetwork, review: {}, waiting: true)
                }
                Spacer()
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 42, weight: .light)).foregroundStyle(Color.accentColor)
                Text(model.busy ? model.activity : "SFTP").font(.title2.weight(.medium)).padding(.top, 12)
                if model.busy {
                    ProgressView().controlSize(.small).padding()
                    Button("Cancel") { model.cancel() }
                } else if model.requirement == nil {
                    Button("Connect", systemImage: "bolt.fill") { model.connect() }
                        .buttonStyle(.borderedProminent).tint(.accentColor).padding(.top, 8)
                }
                Spacer()
            } else {
                navigationBar
                Divider()
                tools
                if let error = model.error { ErrorStrip(message: error, dismiss: { model.error = nil }) }
                Table(model.visibleEntries, selection: $model.selection) {
                    TableColumn("Name") { entry in
                        Label(entry.name, systemImage: icon(entry))
                            .foregroundStyle(entry.kind == .directory ? Color.accentColor : Color.primary)
                    }.width(min: 160, ideal: 340)
                    TableColumn("Size") { entry in
                        Text(formattedSize(entry))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }.width(min: 70, ideal: 90, max: 120)
                    TableColumn("Modified") { entry in
                        Text(entry.modified?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                            .foregroundStyle(.secondary)
                    }.width(min: 150, ideal: 170, max: 210)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let entry = model.entries.first(where: { ids.contains($0.id) }) {
                        if entry.kind == .directory || entry.kind == .symbolicLink {
                            Button("Open Folder", systemImage: "folder") { model.navigate(entry.path) }
                        }
                        if entry.kind != .directory {
                            Button("Download", systemImage: "arrow.down.to.line") { download(entry) }
                        }
                        Button("Rename", systemImage: "pencil") { rename(entry) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                    }
                } primaryAction: { ids in
                    guard !model.busy, let entry = model.entries.first(where: { ids.contains($0.id) }) else { return }
                    if entry.kind == .directory || entry.kind == .symbolicLink {
                        model.navigate(entry.path)
                    } else {
                        download(entry)
                    }
                }
                .overlay {
                    if model.visibleEntries.isEmpty && !model.busy {
                        Text("Empty folder").foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                Divider()
                statusBar
            }
        }
        .sheet(isPresented: $editingName) {
            VStack(alignment: .leading, spacing: 18) {
                Text(renaming == nil ? "New Folder" : "Rename").font(.title3.weight(.semibold))
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { editingName = false }.keyboardShortcut(.cancelAction)
                    Button(renaming == nil ? "Create" : "Rename") {
                        if let entry = renaming { model.rename(entry, name: name) } else { model.createDirectory(name) }
                        editingName = false
                    }
                    .buttonStyle(.borderedProminent).tint(.accentColor)
                    .keyboardShortcut(.defaultAction).disabled(name.isEmpty)
                }
            }.padding(24).frame(width: 360)
        }
        .confirmationDialog("Delete '\(deleting?.name ?? "")'?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry = deleting { model.remove(entry) }
                deleting = nil
            }
        } message: { Text("This permanently deletes the remote item. Only empty folders can be deleted.") }
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            iconButton("Go up", "arrow.up", action: model.up).disabled(model.path == "/" || model.busy)
            iconButton("Home folder", "house", action: model.home).disabled(model.busy)
            TextField("Remote path", text: $model.pathInput)
                .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder)
                .onSubmit { model.navigate(model.pathInput) }.disabled(model.busy)
            iconButton("Refresh", "arrow.clockwise", action: model.refresh).disabled(model.busy)
            iconButton("Disconnect", "stop.circle", action: model.disconnect)
        }.padding(12)
    }

    private var tools: some View {
        HStack(spacing: 14) {
            Button("Upload", systemImage: "arrow.up.to.line", action: upload)
            Button("Download", systemImage: "arrow.down.to.line") {
                if let entry = model.selectedEntry { download(entry) }
            }.disabled(model.selectedEntry == nil || model.selectedEntry?.kind == .directory)
            Divider().frame(height: 18)
            iconButton("New folder", "folder.badge.plus") { renaming = nil; name = ""; editingName = true }
            iconButton("Rename", "pencil") { if let entry = model.selectedEntry { rename(entry) } }
                .disabled(model.selectedEntry == nil)
            iconButton("Delete", "trash") { deleting = model.selectedEntry }.disabled(model.selectedEntry == nil)
            Spacer(minLength: 8)
            Toggle("Hidden files", isOn: $model.showHidden).toggleStyle(.checkbox).font(.caption)
        }
        .buttonStyle(.borderless).disabled(model.busy)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.busy { ProgressView().controlSize(.mini) }
            Text(model.busy ? model.activity : "\(model.visibleEntries.count) items").lineLimit(1)
            Spacer(minLength: 8)
            if let progress = model.progress {
                ProgressView(value: progress).frame(width: 100)
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.transferred), countStyle: .file))
                    .monospacedDigit()
            } else if !model.busy {
                Text(model.activity).foregroundStyle(.secondary)
            }
            if model.busy { iconButton("Cancel operation", "xmark.circle", action: model.cancel) }
        }.font(.caption).padding(12).frame(height: 42)
    }

    private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 20, height: 20) }
            .help(title).accessibilityLabel(title)
    }

    private func icon(_ entry: RemoteEntry) -> String {
        switch entry.kind {
        case .directory: "folder.fill"
        case .symbolicLink: "link"
        case .file: "doc"
        }
    }

    private func formattedSize(_ entry: RemoteEntry) -> String {
        guard entry.kind != .directory, let size = entry.size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)
    }

    private func rename(_ entry: RemoteEntry) { renaming = entry; name = entry.name; editingName = true }

    private func upload() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.begin { if $0 == .OK { model.upload(panel.urls) } }
    }

    private func download(_ entry: RemoteEntry) {
        guard !model.busy else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        panel.prompt = "Download"
        panel.begin { if $0 == .OK, let url = panel.url { model.download(entry, to: url) } }
    }
}
