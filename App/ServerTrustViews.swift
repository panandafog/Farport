import FarportCore
import SwiftUI

struct ServerTrustPresentation: View {
    @ObservedObject var model: ServerTrustModel
    let hosts: [SavedHost]

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: $model.challenge, onDismiss: model.nextChallenge) { challenge in
                ServerTrustPrompt(model: model, challenge: challenge)
            }
            .sheet(isPresented: $model.showingKeys, onDismiss: model.nextChallenge) {
                ServerKeysView(model: model, endpoints: Array(Set(hosts.map { ServerEndpoint($0.profile) }))
                    .sorted { $0.displayName < $1.displayName })
            }
    }
}

private struct ServerTrustPrompt: View {
    @ObservedObject var model: ServerTrustModel
    let challenge: HostKeyChallenge
    @State private var forgetting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(challenge.trusted == nil ? "Verify Server Identity" : "Server Key Changed",
                  systemImage: challenge.trusted == nil ? "lock.shield" : "exclamationmark.shield.fill")
                .font(.title2).foregroundStyle(challenge.trusted == nil ? Color.primary : .red)
            Text(challenge.endpoint.displayName).font(.headline).textSelection(.enabled)
            Text(challenge.trusted == nil ?
                "This is the first connection to this server. Compare the fingerprint with a trusted source " +
                "before continuing." :
                "Connection blocked. This may indicate server replacement or an impersonation attack. " +
                "Do not forget the old key until you have verified the change independently.")
            fingerprint("Presented Key", key: challenge.presented)
            if let trusted = challenge.trusted { fingerprint("Trusted Key", key: trusted) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel, action: model.cancelChallenge).keyboardShortcut(.cancelAction)
                Spacer()
                if challenge.trusted == nil {
                    Button(model.canContinue ? "Trust & Connect" : "Trust Server", systemImage: "checkmark.shield") {
                        model.trust(challenge, continueConnection: model.canContinue)
                    }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Forget Old Key", systemImage: "trash", role: .destructive) { forgetting = true }
                }
            }
        }
        .padding(24).frame(width: 580)
        .confirmationDialog("Forget the trusted key for \(challenge.endpoint.displayName)?",
                            isPresented: $forgetting, titleVisibility: .visible) {
            Button("Forget Key", role: .destructive) {
                if let trusted = challenge.trusted { model.forget(challenge.endpoint, key: trusted) }
            }
        }
    }

    private func fingerprint(_ title: String, key: ServerHostKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title + " (" + key.algorithm + ")").font(.subheadline).foregroundStyle(.secondary)
            Text(key.fingerprint).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        }
    }
}

private struct ServerKeysView: View {
    @ObservedObject var model: ServerTrustModel
    let endpoints: [ServerEndpoint]
    @State private var forgetting: ServerEndpoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Server Keys").font(.title2)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(endpoints, id: \.self) { endpoint in
                        keyRow(endpoint)
                        Divider()
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Done") { model.showingKeys = false }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 620, height: 420)
        .confirmationDialog("Forget the trusted server key?", isPresented: Binding(
            get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }
        ), titleVisibility: .visible) {
            Button("Forget Key", role: .destructive) {
                if let endpoint = forgetting, let key = model.keys[endpoint] { model.forget(endpoint, key: key) }
                forgetting = nil
            }
        }
    }

    private func keyRow(_ endpoint: ServerEndpoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(endpoint.displayName).fontWeight(.medium)
                Text(model.keys[endpoint]?.fingerprint ?? "Not trusted")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .id(model.keys[endpoint]?.fingerprint ?? "untrusted")
            }
            Spacer()
            Button { forgetting = endpoint } label: { Image(systemName: "trash") }
                .help("Forget server key").accessibilityLabel("Forget server key")
                .disabled(model.keys[endpoint] == nil).buttonStyle(.borderless)
        }.padding(.vertical, 12).accessibilityElement(children: .contain)
    }
}
