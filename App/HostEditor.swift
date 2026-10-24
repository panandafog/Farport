import FarportCore
import SwiftUI
import UniformTypeIdentifiers

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: SavedHost
    @State private var port: String
    @State private var error: String?
    @State private var keyExpanded = false
    @State private var emptyPasswordConfirmed = false
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
        VStack(spacing: 0) {
            HStack {
                Text(host.profile.hostname.isEmpty ? "New Host" : "Edit Host").font(.title2.weight(.semibold))
                Spacer()
                Image(systemName: "server.rack").font(.title2).foregroundStyle(Color.accentColor)
            }.padding(24)
            Divider()
            Form {
                Section("Connection") {
                    TextField("Name", text: $host.profile.name, prompt: Text("Development server"))
                    TextField("Hostname", text: $host.profile.hostname, prompt: Text("server.example.com"))
                    TextField("Port", text: $port)
                    TextField("Username", text: $host.profile.username)
                    Picker("Connect through", selection: jumpSelection) {
                        Text("Direct connection").tag(UUID?.none)
                        ForEach(jumpOptions) { jump in
                            Text(jump.profile.displayName).tag(Optional(jump.id))
                        }
                        if let id = host.profile.jumpHostIDs.first, !jumpOptions.contains(where: { $0.id == id }) {
                            Text("Unavailable jump host").tag(Optional(id))
                        }
                    }
                }
                Section("Authentication") {
                    Picker("Method", selection: $host.profile.authentication) {
                        Text("Password").tag(AuthenticationKind.password)
                        Text("Private Key").tag(AuthenticationKind.privateKey)
                    }
                    if host.profile.authentication == .password {
                        SecureField("Password", text: $host.credentials.password)
                        if !host.credentialsConfigured && host.credentials.password.isEmpty {
                            Toggle("Use an empty password", isOn: $emptyPasswordConfirmed)
                        }
                    } else {
                        HStack {
                            Label(
                                host.credentials.privateKey.isEmpty ? "No key selected" : "Private key saved",
                                systemImage: "key"
                            )
                            Spacer()
                            Button("Import Key", systemImage: "square.and.arrow.down", action: importKey)
                        }
                        DisclosureGroup("Key contents", isExpanded: $keyExpanded) {
                            TextEditor(text: $host.credentials.privateKey)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 110)
                        }
                        SecureField("Passphrase", text: $host.credentials.passphrase)
                    }
                }
                Section("Terminal") {
                    Picker("Session", selection: $host.profile.terminalResumeStrategy) {
                        Text("Standard SSH").tag(TerminalResumeStrategy.none)
                        Text("Persistent (tmux)").tag(TerminalResumeStrategy.tmux)
                    }
                    if host.profile.terminalResumeStrategy == .tmux {
                        Text("Requires tmux on the server. Detaching keeps remote programs running.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Files") {
                    TextField("Initial directory", text: $host.profile.initialDirectory, prompt: Text("."))
                }
                Section("Notes") {
                    TextField("Notes", text: $host.profile.notes, axis: .vertical).lineLimit(2...4)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            if let error { ErrorStrip(message: error, dismiss: { self.error = nil }) }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Host", action: saveHost).buttonStyle(.borderedProminent).tint(.accentColor)
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .frame(width: 540, height: keyExpanded && host.profile.authentication == .privateKey ? 780 : 650)
    }

    private var jumpSelection: Binding<UUID?> {
        Binding(get: { host.profile.jumpHostIDs.first }, set: { host.profile.jumpHostIDs = $0.map { [$0] } ?? [] })
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
        guard let value = Int(port) else { error = "Enter a valid port number."; return }
        host.profile.port = value
        host.profile.hostname = host.profile.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        host.profile.username = host.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        host.profile.name = host.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.profile.authentication == .password &&
            (!host.credentials.password.isEmpty || emptyPasswordConfirmed) ||
            host.profile.authentication == .privateKey && !host.credentials.privateKey.isEmpty {
            host.credentialsConfigured = true
        }
        do { try save(host); dismiss() } catch { self.error = error.localizedDescription }
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select an OpenSSH private key"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                host.credentials.privateKey = try String(contentsOf: url, encoding: .utf8)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
