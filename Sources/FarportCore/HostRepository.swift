import Foundation

public protocol HostRepository {
    func load() throws -> [SavedHost]
    func save(_ hosts: [SavedHost]) throws
}

// Legacy plaintext codec for import/test fixtures. Application storage uses ProtectedHostRepository.
public struct JSONHostRepository: HostRepository {
    public let url: URL

    private struct Document: Codable {
        var schemaVersion = 3
        var hosts: [SavedHost]
    }

    public init(url: URL) { self.url = url }

    public func load() throws -> [SavedHost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard (1...3).contains(document.schemaVersion) else {
            throw HarborError.message("This host library was saved by a newer version of Farport.")
        }
        return document.hosts
    }

    public func save(_ hosts: [SavedHost]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Document(hosts: hosts)).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
