import HarborCore
import SwiftUI

struct TerminalTabs: View {
    @ObservedObject var model: WorkspaceModel
    @State private var renaming: TerminalTab?

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(model.tabs) { tab in
                            tabView(tab).id(tab.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.selectedTerminalID) { _, selected in
                    if let selected { reader.scrollTo(selected, anchor: .center) }
                }
                .onAppear {
                    if let selected = model.selectedTerminalID { reader.scrollTo(selected, anchor: .center) }
                }
            }
            Button { model.addTerminal() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).frame(width: 40, height: 38)
                .help("New terminal tab (Command-T)").accessibilityLabel("New terminal tab")
        }
        .frame(height: 38)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .sheet(item: $renaming) { tab in
            RenameTerminalSheet(tab: tab) { title in
                model.renameTerminal(tab.id, title: title)
            }
        }
    }

    private func tabView(_ tab: TerminalTab) -> some View {
        let selected = model.selectedTerminalID == tab.id
        return HStack(spacing: 0) {
            Button {
                model.selectedTerminalID = tab.id
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                    Text(tab.title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(tab.title)
            .accessibilityLabel(tab.title).accessibilityAddTraits(selected ? [.isSelected] : [])
            Button { model.closeTerminal(tab.id) } label: { Image(systemName: "xmark").font(.caption) }
                .buttonStyle(.plain).frame(width: 30, height: 38)
                .help("Close \(tab.title)").accessibilityLabel("Close \(tab.title)")
        }
        .frame(width: 172, height: 38)
        .background(selected ? Color.accentColor.opacity(0.1) : Color.clear)
        .overlay(alignment: .bottom) {
            if selected { Rectangle().fill(.teal).frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Divider() }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renaming = tab }
            Button("Close Tab", systemImage: "xmark") { model.closeTerminal(tab.id) }
        }
    }

}

private struct RenameTerminalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let save: (String) -> Void

    init(tab: TerminalTab, save: @escaping (String) -> Void) {
        _name = State(initialValue: tab.title)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Terminal").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit(rename)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: rename).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 340)
    }

    private func rename() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        save(name)
        dismiss()
    }
}
