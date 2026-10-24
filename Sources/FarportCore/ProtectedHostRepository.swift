import FarportLocalization
import Foundation

public struct ProtectedHostRepository: HostRepository {
    public let url: URL
    private let secrets: any SecretStore

    private struct Header: Decodable { let schemaVersion: Int }
    private struct Document: Codable {
        var schemaVersion = 5
        let hosts: [ProtectedHost]
    }

    public init(url: URL, secrets: any SecretStore) { self.url = url; self.secrets = secrets }

    public func load() throws -> [SavedHost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        if (4...5).contains(version) {
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
        if (4...5).contains(version) { return try JSONDecoder().decode(Document.self, from: data).hosts }
        guard (1...3).contains(version) else { throw HarborError.message(L10n.text("Unsupported host library.")) }
        _ = try JSONHostRepository(url: url).load()
        return []
    }
}
