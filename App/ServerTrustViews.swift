import FarportCore
import FarportLocalization
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
            Label(challenge.trusted == nil ? L10n.text("Verify Server Identity") : L10n.text("Server Key Changed"),
                  systemImage: challenge.trusted == nil ? "lock.shield" : "exclamationmark.shield.fill")
                .font(.title2).foregroundStyle(challenge.trusted == nil ? Color.primary : .red)
            Text(challenge.endpoint.displayName).font(.headline).textSelection(.enabled)
            Text(challenge.trusted == nil ?
                L10n.text(
                    "This is the first connection to this server. Compare the fingerprint with a trusted " +
                    "source before continuing."
                ) :
                L10n.text(
                    "Connection blocked. This may indicate server replacement or an impersonation attack. " +
                    "Do not forget the old key until you have verified the change independently."
                ))
            fingerprint(L10n.text("Presented Key"), key: challenge.presented)
            if let trusted = challenge.trusted { fingerprint(L10n.text("Trusted Key"), key: trusted) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("Cancel"), role: .cancel, action: model.cancelChallenge)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if challenge.trusted == nil {
                    Button(model.canContinue ? L10n.text("Trust & Connect") : L10n.text("Trust Server"),
                           systemImage: "checkmark.shield") {
                        model.trust(challenge, continueConnection: model.canContinue)
                    }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(L10n.text("Forget Old Key"), systemImage: "trash", role: .destructive) { forgetting = true }
                }
            }
        }
        .padding(24).frame(width: 580)
        .confirmationDialog(L10n.text("Forget the trusted key for %@?", challenge.endpoint.displayName),
                            isPresented: $forgetting, titleVisibility: .visible) {
            Button(L10n.text("Forget Key"), role: .destructive) {
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
            Text(L10n.text("Server Keys")).font(.title2)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(endpoints, id: \.self) { endpoint in
                        keyRow(endpoint)
                        Divider()
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button(L10n.text("Done")) { model.showingKeys = false }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 620, height: 420)
        .confirmationDialog(L10n.text("Forget the trusted server key?"), isPresented: Binding(
            get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.text("Forget Key"), role: .destructive) {
                if let endpoint = forgetting, let key = model.keys[endpoint] { model.forget(endpoint, key: key) }
                forgetting = nil
            }
        }
    }

    private func keyRow(_ endpoint: ServerEndpoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(endpoint.displayName).fontWeight(.medium)
                Text(model.keys[endpoint]?.fingerprint ?? L10n.text("Not trusted"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .id(model.keys[endpoint]?.fingerprint ?? "untrusted")
            }
            Spacer()
            Button { forgetting = endpoint } label: { Image(systemName: "trash") }
                .help(L10n.text("Forget server key")).accessibilityLabel(L10n.text("Forget server key"))
                .disabled(model.keys[endpoint] == nil).buttonStyle(.borderless)
        }.padding(.vertical, 12).accessibilityElement(children: .contain)
    }
}
