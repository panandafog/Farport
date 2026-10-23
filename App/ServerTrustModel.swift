import HarborCore
import HarborSecurity
import SwiftUI

struct AppSecretStore: SecretStore {
    func data(for account: String) throws -> Data? { try KeychainSecretStore.shared().data(for: account) }
    func insert(_ data: Data, for account: String) throws {
        try KeychainSecretStore.shared().insert(data, for: account)
    }
    func remove(_ account: String) throws { try KeychainSecretStore.shared().remove(account) }
    func remove(_ account: String, matching expected: Data) throws {
        try KeychainSecretStore.shared().remove(account, matching: expected)
    }
}

@MainActor
final class ServerTrustModel: ObservableObject {
    @Published var challenge: HostKeyChallenge?
    @Published var showingKeys = false
    @Published var error: String?
    @Published private(set) var keys: [ServerEndpoint: ServerHostKey] = [:]
    private struct Continuation {
        let endpoint: ServerEndpoint
        let retry: () -> Void
    }
    @Published private var continuations: [String: Continuation] = [:]
    private let repository: KnownHostRepository
    private var queued: [HostKeyChallenge] = []
    private var afterDismiss: (() -> Void)?

    init(secrets: any SecretStore) { repository = KnownHostRepository(secrets: secrets) }

    var verifier: HostKeyVerifier {
        let repository = repository
        return { endpoint, key in try repository.verify(endpoint, key: key) }
    }

    var canContinue: Bool { challenge.map { $0.trusted == nil && continuations[$0.id] != nil } ?? false }

    func present(_ value: HostKeyChallenge, retry: (() -> Void)? = nil) {
        if let retry, continuations[value.id] == nil {
            continuations[value.id] = Continuation(endpoint: value.endpoint, retry: retry)
        }
        guard challenge?.id != value.id, !queued.contains(where: { $0.id == value.id }) else { return }
        error = nil
        if challenge == nil, !showingKeys { challenge = value } else { queued.append(value) }
    }

    func nextChallenge() {
        if challenge == nil { continuations = continuations.filter { entry in queued.contains { $0.id == entry.key } } }
        guard challenge == nil, !showingKeys else { return }
        let retry = afterDismiss
        afterDismiss = nil
        retry?()
        if !queued.isEmpty { challenge = queued.removeFirst() }
    }

    func trust(_ value: HostKeyChallenge, continueConnection: Bool = false) {
        error = nil
        do {
            try repository.trust(value)
            keys[value.endpoint] = value.presented
            let retry = continuations.removeValue(forKey: value.id)
            if continueConnection, let retry { afterDismiss = retry.retry }
            challenge = nil
        } catch { self.error = error.localizedDescription }
    }

    func cancelChallenge() {
        if let challenge { continuations.removeValue(forKey: challenge.id) }
        challenge = nil
    }

    func showKeys(hosts: [SavedHost]) {
        error = nil
        do {
            var loaded: [ServerEndpoint: ServerHostKey] = [:]
            for host in hosts {
                let endpoint = ServerEndpoint(host.profile)
                loaded[endpoint] = try repository.key(for: endpoint)
            }
            keys = loaded
        } catch { self.error = error.localizedDescription }
        showingKeys = true
    }

    func storedKey(_ endpoint: ServerEndpoint) throws -> ServerHostKey? { try repository.key(for: endpoint) }

    func forget(_ endpoint: ServerEndpoint, key: ServerHostKey) {
        error = nil
        do {
            try repository.forget(endpoint, expected: key)
            keys.removeValue(forKey: endpoint)
            if challenge?.endpoint == endpoint { challenge = nil }
            queued.removeAll { $0.endpoint == endpoint }
            continuations = continuations.filter { $0.value.endpoint != endpoint }
        } catch { self.error = error.localizedDescription }
    }
}
