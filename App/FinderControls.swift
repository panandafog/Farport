import FarportCore
import FarportLocalization
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
                Button(L10n.text("Cancel"), systemImage: "xmark") { model.cancel() }
            }
            Button(L10n.text("Connect Folder to Finder"), systemImage: "folder.badge.plus") {
                folder = currentFolder.isEmpty ? host.profile.initialDirectory : currentFolder
                model.reload()
                showingFolder = true
            }
            .disabled(model.busy)
            ForEach(locations) { location in
                Section(locationTitle(location)) {
                    Button(L10n.text("Open in Finder"), systemImage: "folder") { model.open(location) }
                    Button(L10n.text("Refresh"), systemImage: "arrow.clockwise") { model.refresh(location) }
                    Button(L10n.text("Disconnect"), systemImage: "eject") { model.disconnect(location) }
                }
                .disabled(model.busy)
            }
        } label: {
            if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: "folder.badge.gearshape") }
        }
        .frame(width: 40)
        .help(L10n.text("Finder connections")).accessibilityLabel(L10n.text("Finder connections"))
        .task { model.reload() }
        .sheet(isPresented: $showingFolder) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("Connect to Finder")).font(.title3.weight(.semibold))
                Form {
                    LabeledContent(L10n.text("Host"), value: host.profile.displayName)
                    TextField(L10n.text("Remote folder"), text: $folder)
                    Picker(L10n.text("Access"), selection: $access) {
                        Text(L10n.text("Read Only")).tag(FinderLocation.Access.readOnly)
                        Text(L10n.text("Read & Write")).tag(FinderLocation.Access.readWrite)
                    }.pickerStyle(.segmented)
                }
                HStack {
                    Spacer()
                    Button(L10n.text("Cancel")) { showingFolder = false }.keyboardShortcut(.cancelAction)
                    Button(L10n.text("Connect"), systemImage: "folder.badge.plus") {
                        showingFolder = false
                        model.connect(host: host, library: hosts, folder: folder, access: access)
                    }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.accentColor)
                }
            }.padding(24).frame(width: 440)
        }
        .alert("Finder", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L10n.text("OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func locationTitle(_ location: FinderLocation) -> String {
        location.access == .readOnly ? L10n.text("%@ (Read Only)", location.rootPath) : location.rootPath
    }
}
