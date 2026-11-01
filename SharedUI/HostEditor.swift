import FarportCore
import FarportLocalization
import FarportSessions
import FarportSSH
import SwiftUI
import UniformTypeIdentifiers

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HostEditorDraft
    @State private var error: String?
    @State private var errorTitle = ""
    @State private var keyExpanded = false
    @State private var importingKey = false
    let hosts: [SavedHost]
    private let editorTitle: String
    let save: (SavedHost) throws -> Void

    init(host: SavedHost, hosts: [SavedHost], save: @escaping (SavedHost) throws -> Void) {
        self.hosts = hosts
        _draft = State(initialValue: HostEditorDraft(host: host, hosts: hosts))
        editorTitle = hosts.contains { $0.id == host.id } ? L10n.text("Edit Host") : L10n.text("New Host")
        self.save = save
    }

    var body: some View {
        editor
            .alert(errorTitle, isPresented: errorPresented) {
                Button(L10n.text("OK")) { error = nil }
            } message: {
                Text(error ?? "")
            }
    }

    private var editor: some View {
        #if os(iOS)
            NavigationStack {
                editorContent
                    #if DEBUG
                    .accessibilityIdentifier(ScreenshotSupport.scene == .hostSettings ? "screen.host-settings" : "")
                    #endif
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
                                .disabled(!canSave)
                        }
                    }
                    .fileImporter(isPresented: $importingKey, allowedContentTypes: [.item]) { result in
                        do { try readKey(result.get()) } catch {
                            showError(error, title: "Could not import private key")
                        }
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
                editorContent
                    #if DEBUG
                    .accessibilityIdentifier(ScreenshotSupport.scene == .hostSettings ? "screen.host-settings" : "")
                    #endif
                Divider()
                HStack {
                    Spacer()
                    Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L10n.text("Save Host"), action: saveHost).buttonStyle(.borderedProminent).tint(.accentColor)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }.padding(20)
            }
            .frame(width: 540, height: keyExpanded && draft.host.profile.authentication == .privateKey ? 780 : 650)
        #endif
    }

    private var validation: Result<SavedHost, Error> {
        Result {
            let candidate = try draft.validatedHost(in: hosts)
            try SSHCredentialValidation.validateFormat(for: candidate)
            return candidate
        }
    }

    private var canSave: Bool {
        if case .success = validation { return true }
        return false
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            form
            if case .failure(let issue) = validation {
                Divider()
                Label(issue.localizedDescription, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .layoutPriority(1)
                    .accessibilityIdentifier("host-editor.validation")
            }
        }
    }

    private var form: some View {
        Form {
            Section(L10n.text("Connection")) {
                profileField("Name", text: $draft.host.profile.name, prompt: L10n.text("Development server"))
                profileField("Hostname", text: $draft.host.profile.hostname, prompt: "server.example.com")
                profileField("Port", text: $draft.port)
                profileField("Username", text: $draft.host.profile.username)
                Picker(L10n.text("Connect through"), selection: jumpSelection) {
                    Text(L10n.text("Direct connection")).tag(UUID?.none)
                    ForEach(jumpOptions) { jump in
                        Text(jump.profile.displayName).tag(Optional(jump.id))
                    }
                    if let id = draft.host.profile.jumpHostIDs.first, !jumpOptions.contains(where: { $0.id == id }) {
                        Text(L10n.text("Unavailable jump host")).tag(Optional(id))
                    }
                }
            }
            Section(L10n.text("Authentication")) {
                Picker(L10n.text("Method"), selection: $draft.host.profile.authentication) {
                    Text(L10n.text("Password")).tag(AuthenticationKind.password)
                    Text(L10n.text("Private Key")).tag(AuthenticationKind.privateKey)
                }
                if draft.host.profile.authentication == .password {
                    SecureField(L10n.text("Password"), text: $draft.host.credentials.password)
                    if draft.host.credentials.password.isEmpty {
                        Toggle(L10n.text("Use an empty password"), isOn: $draft.emptyPasswordConfirmed)
                    }
                } else {
                    HStack {
                        Label(
                            draft.host.credentials.privateKey.isEmpty
                                ? L10n.text("No key selected") : L10n.text("Private key saved"),
                            systemImage: "key"
                        )
                        Spacer()
                        Button(L10n.text("Import Key"), systemImage: "square.and.arrow.down", action: importKey)
                    }
                    DisclosureGroup(L10n.text("Key contents"), isExpanded: $keyExpanded) {
                        TextEditor(text: $draft.host.credentials.privateKey)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 110)
                    }
                    SecureField(L10n.text("Passphrase"), text: $draft.host.credentials.passphrase)
                }
            }
            Section(L10n.text("Terminal")) {
                Picker(L10n.text("Session"), selection: $draft.host.profile.terminalResumeStrategy) {
                    Text(L10n.text("Standard SSH")).tag(TerminalResumeStrategy.none)
                    Text(L10n.text("Persistent (tmux)")).tag(TerminalResumeStrategy.tmux)
                }
                if draft.host.profile.terminalResumeStrategy == .tmux {
                    Text(L10n.text("Requires tmux on the server. Detaching keeps remote programs running."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
                Section(L10n.text("Files")) {
                    TextField(L10n.text("Initial directory"), text: $draft.host.profile.initialDirectory,
                              prompt: Text("."))
                }
            #endif
            Section(L10n.text("Notes")) {
                TextField(L10n.text("Notes"), text: $draft.host.profile.notes, axis: .vertical).lineLimit(2...4)
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }

    private var jumpSelection: Binding<UUID?> {
        Binding(get: { draft.host.profile.jumpHostIDs.first }, set: {
            draft.host.profile.jumpHostIDs = $0.map { [$0] } ?? []
        })
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
            guard candidate.id != draft.host.id, candidate.profile.terminalProvider == "ssh" else { return false }
            var target = draft.host
            target.profile.jumpHostIDs = [candidate.id]
            return (try? ConnectionRoute(to: target, library: hosts)) != nil
        }
    }

    private func saveHost() {
        // Revalidate on activation as well as disabling the visible button/keyboard shortcut.
        guard case .success(let candidate) = validation else { return }
        do {
            try save(candidate)
            dismiss()
        } catch { showError(error, title: "Could not save host") }
    }

    private func showError(_ error: Error, title: String) {
        errorTitle = L10n.text(title)
        self.error = error.localizedDescription
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
                    showError(error, title: "Could not import private key")
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
        var candidate = draft.host
        candidate.credentials.privateKey = try String(contentsOf: url, encoding: .utf8)
        try SSHCredentialValidation.validateFormat(for: candidate)
        draft.host.credentials.privateKey = candidate.credentials.privateKey
    }
}
