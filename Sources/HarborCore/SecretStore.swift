import Foundation

public protocol SecretStore: Sendable {
    func data(for account: String) throws -> Data?
    func insert(_ data: Data, for account: String) throws
    func remove(_ account: String) throws
    func remove(_ account: String, matching expected: Data) throws
}

public struct ProtectedHost: Codable, Sendable {
    public let profile: HostProfile
    public let credentialReference: String
    private let configured: Bool?

    public func resolve(using secrets: any SecretStore) throws -> SavedHost {
        try validateReference()
        guard let data = try secrets.data(for: credentialReference) else {
            throw HarborError.message("Credentials are missing from Keychain. The saved profile was not changed.")
        }
        return SavedHost(profile: profile, credentials: try JSONDecoder().decode(HostCredentials.self, from: data),
                         credentialsConfigured: configured ?? true)
    }

    static func protect(_ hosts: [SavedHost], previous: [ProtectedHost], secrets: any SecretStore) throws -> [Self] {
        try hosts.map { host in
            let data = try JSONEncoder().encode(host.credentials)
            if let old = previous.first(where: { $0.profile.id == host.id }),
               let saved = try old.credentialData(using: secrets),
               try JSONDecoder().decode(HostCredentials.self, from: saved) == host.credentials {
                return ProtectedHost(profile: host.profile, credentialReference: old.credentialReference,
                                     configured: host.credentialsConfigured)
            }
            let account = "credentials." + UUID().uuidString
            try secrets.insert(data, for: account)
            guard try secrets.data(for: account) == data else {
                throw HarborError.message("Keychain verification failed. The original file was not changed.")
            }
            return ProtectedHost(profile: host.profile, credentialReference: account,
                                 configured: host.credentialsConfigured)
        }
    }

    static func retire(_ previous: [Self], keeping current: [Self], secrets: any SecretStore) {
        let retained = Set(current.map(\.credentialReference))
        for old in previous where !retained.contains(old.credentialReference) {
            // Metadata is already committed. Cleanup failure must not invalidate the new credential references.
            if (try? old.validateReference()) != nil { try? secrets.remove(old.credentialReference) }
        }
    }

    private func credentialData(using secrets: any SecretStore) throws -> Data? {
        try validateReference()
        return try secrets.data(for: credentialReference)
    }

    private func validateReference() throws {
        guard credentialReference.hasPrefix("credentials."),
              UUID(uuidString: String(credentialReference.dropFirst("credentials.".count))) != nil else {
            throw HarborError.message("Invalid saved credential reference. The file was not changed.")
        }
    }
}
