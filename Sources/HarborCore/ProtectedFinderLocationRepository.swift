import Foundation

public struct ProtectedFinderLocationRepository: Sendable {
    public let directory: URL
    private let secrets: any SecretStore
    private let migrateLegacy: Bool
    private struct Header: Decodable { let schemaVersion: Int }
    private struct Document: Codable {
        var schemaVersion = 2
        let id: UUID
        let hostID: UUID
        let rootPath: String
        let access: FinderLocation.Access
        let hosts: [ProtectedHost]
    }

    public init(directory: URL, secrets: any SecretStore, migrateLegacy: Bool = false) {
        self.directory = directory; self.secrets = secrets; self.migrateLegacy = migrateLegacy
    }

    public func load(_ id: UUID) throws -> FinderLocation {
        let data = try Data(contentsOf: url(id))
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        if version == 1 {
            guard migrateLegacy else {
                throw HarborError.message("Open Harbor to migrate this Finder connection to Keychain.")
            }
            let location = try FinderLocationRepository(directory: directory).load(id)
            try save(location)
            return location
        }
        guard version == 2 else { throw HarborError.message("Unsupported Finder connection configuration.") }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.id == id else { throw HarborError.message("Invalid Finder connection identifier.") }
        let hosts = try document.hosts.map { try $0.resolve(using: secrets) }
        guard let host = hosts.first(where: { $0.id == document.hostID }) else { throw FinderReadError.disabled }
        return try FinderLocation(id: id, host: host, library: hosts, rootPath: document.rootPath,
                                   access: document.access)
    }

    public func loadAll() throws -> [FinderLocation] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { file in
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                    throw HarborError.message("Unexpected Finder configuration file.")
                }
                return try load(id)
            }
    }

    public func save(_ location: FinderLocation) throws {
        try location.validate()
        let previous = try references(location.id)
        let hosts = try ProtectedHost.protect(location.hosts, previous: previous, secrets: secrets)
        let document = Document(id: location.id, hostID: location.hostID, rootPath: location.rootPath,
                                 access: location.access, hosts: hosts)
        try PrivateFileStorage.write(try JSONEncoder().encode(document), to: url(location.id))
        ProtectedHost.retire(previous, keeping: hosts, secrets: secrets)
    }

    public func remove(_ id: UUID) throws {
        guard FileManager.default.fileExists(atPath: url(id).path) else { return }
        let previous = try references(id)
        try FileManager.default.removeItem(at: url(id))
        ProtectedHost.retire(previous, keeping: [], secrets: secrets)
    }

    private func references(_ id: UUID) throws -> [ProtectedHost] {
        guard FileManager.default.fileExists(atPath: url(id).path) else { return [] }
        let data = try Data(contentsOf: url(id))
        switch try JSONDecoder().decode(Header.self, from: data).schemaVersion {
        case 1:
            _ = try FinderLocationRepository(directory: directory).load(id)
            return []
        case 2:
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.id == id else { throw FinderReadError.disabled }
            return document.hosts
        default: throw HarborError.message("Unsupported Finder connection configuration.")
        }
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
}
