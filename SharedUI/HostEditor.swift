import FarportCore
import FarportLocalization
import SwiftUI
import UniformTypeIdentifiers

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: SavedHost
    @State private var port: String
    @State private var error: String?
    @State private var keyExpanded = false
    @State private var emptyPasswordConfirmed = false
    @State private var importingKey = false
    let hosts: [SavedHost]
    let save: (SavedHost) throws -> Void

    init(host: SavedHost, hosts: [SavedHost], save: @escaping (SavedHost) throws -> Void) {
        self.hosts = hosts
        var editable = host
        if !editable.credentialsConfigured { editable.credentials = HostCredentials() }
        _host = State(initialValue: editable)
        _port = State(initialValue: String(host.profile.port))
        self.save = save
    }

    var body: some View {
        #if os(iOS)
            NavigationStack {
                form
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .navigationTitle(editorTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("Cancel"), systemImage: "xmark") { dismiss() }
                                .labelStyle(.iconOnly)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.text("Save"), systemImage: "checkmark", action: saveHost)
                                .labelStyle(.iconOnly)
                        }
                    }
                    .fileImporter(isPresented: $importingKey, allowedContentTypes: [.item]) { result in
                        do { try readKey(result.get()) } catch { self.error = error.localizedDescription }
                    }
            }
        #else
            VStack(spacing: 0) {
                HStack {
                    Text(editorTitle)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Image(systemName: "server.rack").font(.title2).foregroundStyle(Color.accentColor)
                }.padding(24)
                Divider()
                form
                Divider()
                HStack {
                    Spacer()
                    Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L10n.text("Save Host"), action: saveHost).buttonStyle(.borderedProminent).tint(.accentColor)
                        .keyboardShortcut(.defaultAction)
                }.padding(20)
            }
            .frame(width: 540, height: keyExpanded && host.profile.authentication == .privateKey ? 780 : 650)
        #endif
    }

    private var editorTitle: String {
        host.profile.hostname.isEmpty ? L10n.text("New Host") : L10n.text("Edit Host")
    }

    private var form: some View {
        Form {
            Section(L10n.text("Connection")) {
                profileField("Name", text: $host.profile.name, prompt: L10n.text("Development server"))
                profileField("Hostname", text: $host.profile.hostname, prompt: "server.example.com")
                profileField("Port", text: $port)
                profileField("Username", text: $host.profile.username)
                Picker(L10n.text("Connect through"), selection: jumpSelection) {
                    Text(L10n.text("Direct connection")).tag(UUID?.none)
                    ForEach(jumpOptions) { jump in
                        Text(jump.profile.displayName).tag(Optional(jump.id))
                    }
                    if let id = host.profile.jumpHostIDs.first, !jumpOptions.contains(where: { $0.id == id }) {
                        Text(L10n.text("Unavailable jump host")).tag(Optional(id))
                    }
                }
            }
            Section(L10n.text("Authentication")) {
                Picker(L10n.text("Method"), selection: $host.profile.authentication) {
                    Text(L10n.text("Password")).tag(AuthenticationKind.password)
                    Text(L10n.text("Private Key")).tag(AuthenticationKind.privateKey)
                }
                if host.profile.authentication == .password {
                    SecureField(L10n.text("Password"), text: $host.credentials.password)
                    if !host.credentialsConfigured && host.credentials.password.isEmpty {
                        Toggle(L10n.text("Use an empty password"), isOn: $emptyPasswordConfirmed)
                    }
                } else {
                    HStack {
                        Label(
                            host.credentials.privateKey.isEmpty
                                ? L10n.text("No key selected") : L10n.text("Private key saved"),
                            systemImage: "key"
                        )
                        Spacer()
                        Button(L10n.text("Import Key"), systemImage: "square.and.arrow.down", action: importKey)
                    }
                    DisclosureGroup(L10n.text("Key contents"), isExpanded: $keyExpanded) {
                        TextEditor(text: $host.credentials.privateKey)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 110)
                    }
                    SecureField(L10n.text("Passphrase"), text: $host.credentials.passphrase)
                }
            }
            Section(L10n.text("Terminal")) {
                Picker(L10n.text("Session"), selection: $host.profile.terminalResumeStrategy) {
                    Text(L10n.text("Standard SSH")).tag(TerminalResumeStrategy.none)
                    Text(L10n.text("Persistent (tmux)")).tag(TerminalResumeStrategy.tmux)
                }
                if host.profile.terminalResumeStrategy == .tmux {
                    Text(L10n.text("Requires tmux on the server. Detaching keeps remote programs running."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
                Section(L10n.text("Files")) {
                    TextField(L10n.text("Initial directory"), text: $host.profile.initialDirectory, prompt: Text("."))
                }
            #endif
            Section(L10n.text("Notes")) {
                TextField(L10n.text("Notes"), text: $host.profile.notes, axis: .vertical).lineLimit(2...4)
                    .labelsHidden()
            }
            if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
        }
        .formStyle(.grouped)
    }

    private var jumpSelection: Binding<UUID?> {
        Binding(get: { host.profile.jumpHostIDs.first }, set: { host.profile.jumpHostIDs = $0.map { [$0] } ?? [] })
    }

    @ViewBuilder
    private func profileField(_ title: String, text: Binding<String>, prompt: String? = nil) -> some View {
        #if os(iOS)
            LabeledContent(L10n.text(title)) {
                TextField(L10n.text(title), text: text, prompt: prompt.map(Text.init(verbatim:)))
                    .multilineTextAlignment(.trailing)
            }
        #else
            TextField(L10n.text(title), text: text, prompt: prompt.map(Text.init(verbatim:)))
        #endif
    }

    private var jumpOptions: [SavedHost] {
        hosts.filter { candidate in
            guard candidate.id != host.id, candidate.profile.terminalProvider == "ssh" else { return false }
            var target = host
            target.profile.jumpHostIDs = [candidate.id]
            return (try? ConnectionRoute(to: target, library: hosts)) != nil
        }
    }

    private func saveHost() {
        guard let value = Int(port) else {
            error = L10n.text("Enter a valid port number.")
            return
        }
        host.profile.port = value
        host.profile.hostname = host.profile.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        host.profile.username = host.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        host.profile.name = host.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.profile.authentication == .password && (!host.credentials.password.isEmpty || emptyPasswordConfirmed)
            || host.profile.authentication == .privateKey && !host.credentials.privateKey.isEmpty {
            host.credentialsConfigured = true
        }
        do {
            try save(host)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func importKey() {
        #if os(iOS)
            importingKey = true
        #else
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.showsHiddenFiles = true
            panel.message = L10n.text("Select an OpenSSH private key")
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try readKey(url)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        #endif
    }

    private func readKey(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576 else {
            throw HarborError.message(L10n.text("The private key file is too large."))
        }
        host.credentials.privateKey = try String(contentsOf: url, encoding: .utf8)
    }
}
