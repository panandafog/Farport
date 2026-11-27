import FarportLocalization
import Foundation

public struct ProtectedHostRepository: HostRepository {
    public let url: URL
    private let secrets: any SecretStore

    private struct Header: Decodable { let schemaVersion: Int }
    private struct Document: Codable {
        var schemaVersion = 7
        let hosts: [ProtectedHost]
    }

    public init(url: URL, secrets: any SecretStore) { self.url = url; self.secrets = secrets }

    public func load() throws -> [SavedHost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        if (4...7).contains(version) {
            let hosts = try JSONDecoder().decode(Document.self, from: data).hosts.map { try $0.resolve(using: secrets) }
            if version == 4 { try save(hosts) }
            return hosts
        }
        guard (1...3).contains(version) else {
            throw HarborError.message(L10n.text("Unsupported host library. The file was not changed."))
        }
        let hosts = try JSONHostRepository(url: url).load()
        try save(hosts)
        return hosts
    }

    public func save(_ hosts: [SavedHost]) throws {
        let previous = try references()
        let protected = try ProtectedHost.protect(hosts, previous: previous, secrets: secrets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFileStorage.write(try encoder.encode(Document(hosts: protected)), to: url)
        ProtectedHost.retire(previous, keeping: protected, secrets: secrets)
    }

    private func references() throws -> [ProtectedHost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        if (4...7).contains(version) { return try JSONDecoder().decode(Document.self, from: data).hosts }
        guard (1...3).contains(version) else { throw HarborError.message(L10n.text("Unsupported host library.")) }
        _ = try JSONHostRepository(url: url).load()
        return []
    }
}

public extension ProtectedHostRepository {
    /// Automation queries never migrate libraries, touch Keychain, or write cloud/workspace state.
    func automationProfiles() throws -> [HostProfile] {
        try HostOrdering.sorted(automationReferences().map(\.profile))
    }

    /// Resolve secrets only for the selected route; an unrelated missing key must not block automation.
    func automationRoute(to id: UUID) throws -> ConnectionRoute {
        let entries = try automationReferences()
        let placeholders = entries.map { SavedHost(profile: $0.profile, credentialsConfigured: false) }
        guard let target = placeholders.first(where: { $0.id == id }) else {
            throw HarborError.message(L10n.text("This saved host no longer exists. Select another host in Shortcuts."))
        }
        let route = try ConnectionRoute(to: target, library: placeholders)
        let ids = Set(route.hosts.map(\.id))
        let resolved = try entries.filter { ids.contains($0.profile.id) }.map { try $0.resolve(using: secrets) }
        guard let host = resolved.first(where: { $0.id == id }) else { throw CancellationError() }
        for endpoint in resolved { try endpoint.validate() }
        return try ConnectionRoute(to: host, library: resolved)
    }

    private func automationReferences() throws -> [ProtectedHost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        guard (4...7).contains(version) else {
            throw HarborError.message(L10n.text("Open Farport to update the host library before using Shortcuts."))
        }
        let entries = try JSONDecoder().decode(Document.self, from: data).hosts
        guard Set(entries.map { $0.profile.id }).count == entries.count else {
            throw HarborError.message(L10n.text("The host library contains duplicate identifiers."))
        }
        return entries
    }
}
