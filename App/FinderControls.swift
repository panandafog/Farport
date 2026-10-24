import FarportCore
import SwiftUI

struct FinderControls: View {
    @ObservedObject var model: FinderModel
    let host: SavedHost
    let hosts: [SavedHost]
    let currentFolder: String
    @State private var showingFolder = false
    @State private var folder = ""
    @State private var access = FinderLocation.Access.readWrite

    private var locations: [FinderLocation] { model.locations.filter { $0.hostID == host.id } }

    var body: some View {
        Menu {
            if model.busy {
                Button("Cancel", systemImage: "xmark") { model.cancel() }
            }
            Button("Connect Folder to Finder", systemImage: "folder.badge.plus") {
                folder = currentFolder.isEmpty ? host.profile.initialDirectory : currentFolder
                model.reload()
                showingFolder = true
            }
            .disabled(model.busy)
            ForEach(locations) { location in
                Section(location.rootPath + (location.access == .readOnly ? " (Read Only)" : "")) {
                    Button("Open in Finder", systemImage: "folder") { model.open(location) }
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refresh(location) }
                    Button("Disconnect", systemImage: "eject") { model.disconnect(location) }
                }
                .disabled(model.busy)
            }
        } label: {
            if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: "folder.badge.gearshape") }
        }
        .frame(width: 40)
        .help("Finder connections").accessibilityLabel("Finder connections")
        .task { model.reload() }
        .sheet(isPresented: $showingFolder) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect to Finder").font(.title3.weight(.semibold))
                Form {
                    LabeledContent("Host", value: host.profile.displayName)
                    TextField("Remote folder", text: $folder)
                    Picker("Access", selection: $access) {
                        Text("Read Only").tag(FinderLocation.Access.readOnly)
                        Text("Read & Write").tag(FinderLocation.Access.readWrite)
                    }.pickerStyle(.segmented)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showingFolder = false }.keyboardShortcut(.cancelAction)
                    Button("Connect", systemImage: "folder.badge.plus") {
                        showingFolder = false
                        model.connect(host: host, library: hosts, folder: folder, access: access)
                    }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.accentColor)
                }
            }.padding(24).frame(width: 440)
        }
        .alert("Finder", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
