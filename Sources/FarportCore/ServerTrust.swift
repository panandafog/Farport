import CryptoKit
import FarportLocalization
import Foundation

public struct ServerEndpoint: Codable, Equatable, Hashable, Sendable {
    public let hostname: String
    public let port: Int
    public init(hostname: String, port: Int) {
        self.hostname = hostname.lowercased()
        self.port = port
    }
    public init(_ profile: HostProfile) { self.init(hostname: profile.hostname, port: profile.port) }
    public var displayName: String { "[\(hostname)]:\(port)" }
    var account: String {
        "server-key." + Data(SHA256.hash(data: Data(displayName.utf8))).base64EncodedString()
    }
}

public struct ServerHostKey: Codable, Equatable, Sendable {
    public let algorithm: String
    public let wireData: Data
    public init(algorithm: String, wireData: Data) { self.algorithm = algorithm; self.wireData = wireData }
    public var fingerprint: String {
        "SHA256:" + Data(SHA256.hash(data: wireData)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}

public struct HostKeyChallenge: Error, LocalizedError, Identifiable, Equatable, Sendable {
    public let endpoint: ServerEndpoint
    public let presented: ServerHostKey
    public let trusted: ServerHostKey?
    public var id: String { endpoint.displayName + presented.fingerprint }
    public init(endpoint: ServerEndpoint, presented: ServerHostKey, trusted: ServerHostKey? = nil) {
        self.endpoint = endpoint; self.presented = presented; self.trusted = trusted
    }
    public var errorDescription: String? {
        let reason = trusted == nil ? L10n.text("Unknown server key") : L10n.text("SERVER KEY CHANGED")
        return L10n.text(
            "%@ for %@. %@ %@. Connection blocked. Verify this fingerprint in Farport before connecting again.",
            reason, endpoint.displayName, presented.algorithm, presented.fingerprint
        )
    }
}

public typealias HostKeyVerifier = @Sendable (ServerEndpoint, ServerHostKey) throws -> Void

public struct KnownHostRepository: Sendable {
    private let secrets: any SecretStore
    public init(secrets: any SecretStore) { self.secrets = secrets }

    public func key(for endpoint: ServerEndpoint) throws -> ServerHostKey? {
        try secrets.data(for: endpoint.account).map { try JSONDecoder().decode(ServerHostKey.self, from: $0) }
    }

    public func verify(_ endpoint: ServerEndpoint, key presented: ServerHostKey) throws {
        let stored = try key(for: endpoint)
        guard stored == presented else {
            throw HostKeyChallenge(endpoint: endpoint, presented: presented, trusted: stored)
        }
    }

    public func trust(_ challenge: HostKeyChallenge) throws {
        guard challenge.trusted == nil else {
            throw HarborError.message(L10n.text(
                "A changed server key cannot be accepted over an existing trusted key."
            ))
        }
        if let current = try key(for: challenge.endpoint) {
            guard current == challenge.presented else { throw HostKeyChallenge(
                endpoint: challenge.endpoint, presented: challenge.presented, trusted: current
            ) }
            return
        }
        do {
            try secrets.insert(try JSONEncoder().encode(challenge.presented), for: challenge.endpoint.account)
        } catch {
            // Concurrent first-use prompts may only converge on the exact same key, never replace a pin.
            guard try key(for: challenge.endpoint) == challenge.presented else { throw error }
        }
    }

    public func forget(_ endpoint: ServerEndpoint, expected: ServerHostKey) throws {
        guard let data = try secrets.data(for: endpoint.account),
              try JSONDecoder().decode(ServerHostKey.self, from: data) == expected else {
            throw HarborError.message(L10n.text("The stored server key changed."))
        }
        try secrets.remove(endpoint.account, matching: data)
    }
}
