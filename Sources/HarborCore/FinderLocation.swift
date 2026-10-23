import Foundation

public struct FinderLocation: Codable, Equatable, Identifiable, Sendable {
    public enum Access: String, Codable, CaseIterable, Sendable { case readOnly, readWrite }
    public let id: UUID
    public let hostID: UUID
    public let name: String
    public let rootPath: String
    public let hosts: [SavedHost]
    private let accessMode: Access?
    public var access: Access { accessMode ?? .readOnly }

    public init(id: UUID = UUID(), host: SavedHost, library: [SavedHost], rootPath: String,
                access: Access = .readOnly) throws {
        self.id = id
        hostID = host.id
        name = host.profile.displayName
        self.rootPath = rootPath
        hosts = try ConnectionRoute(to: host, library: library).hosts
        accessMode = access
        try validate()
    }

    public var host: SavedHost? { hosts.first { $0.id == hostID } }

    public func validate() throws {
        try FinderPath.validateRoot(rootPath)
        guard let host else { throw HarborError.message("Finder host is unavailable.") }
        try hosts.forEach { try $0.validate() }
        _ = try ConnectionRoute(to: host, library: hosts)
    }
}

// Legacy plaintext codec; production Finder configuration uses ProtectedFinderLocationRepository.
public struct FinderLocationRepository: Sendable {
    public let directory: URL

    private struct Document: Codable {
        var schemaVersion = 1
        let location: FinderLocation
    }

    public init(directory: URL) { self.directory = directory }

    public func load(_ id: UUID) throws -> FinderLocation {
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url(id)))
        guard document.schemaVersion == 1, document.location.id == id else {
            throw HarborError.message("Unsupported Finder connection configuration.")
        }
        try document.location.validate()
        return document.location
    }

    public func loadAll() throws -> [FinderLocation] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { file in
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                    throw HarborError.message("Unexpected Finder configuration file.")
                }
                return try load(id)
            }
    }

    public func save(_ location: FinderLocation) throws {
        try location.validate()
        try PrivateFileStorage.write(try JSONEncoder().encode(Document(location: location)), to: url(location.id))
    }

    public func remove(_ id: UUID) throws {
        let file = url(id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
}

enum PrivateFileStorage {
    static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum FinderPath {
    public static let rootIdentifier = "root"

    public static func validateRoot(_ root: String) throws {
        guard root.hasPrefix("/"), root == "/" || !root.hasSuffix("/"),
              !root.contains("\0"), !root.contains("//"),
              !root.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw HarborError.message("Finder requires a canonical absolute remote folder.")
        }
    }

    public static func identifier(_ relativePath: String) throws -> String {
        try validateRelative(relativePath)
        return relativePath.isEmpty ? rootIdentifier : "path." + Data(relativePath.utf8).base64EncodedString()
    }

    public static func relativePath(_ identifier: String) throws -> String {
        if identifier == rootIdentifier { return "" }
        guard identifier.hasPrefix("path."), let data = Data(base64Encoded: String(identifier.dropFirst(5))),
              let path = String(data: data, encoding: .utf8), !path.isEmpty else {
            throw FinderReadError.noSuchItem
        }
        try validateRelative(path)
        guard try self.identifier(path) == identifier else { throw FinderReadError.noSuchItem }
        return path
    }

    public static func remotePath(_ relativePath: String, root: String) throws -> String {
        try validateRoot(root)
        try validateRelative(relativePath)
        return relativePath.isEmpty ? root : (root == "/" ? "/" : root + "/") + relativePath
    }

    public static func parent(_ relativePath: String) -> String {
        relativePath.split(separator: "/").dropLast().joined(separator: "/")
    }

    private static func validateRelative(_ path: String) throws {
        guard path.isEmpty || (!path.hasPrefix("/") && !path.hasSuffix("/") && !path.contains("//")),
              !path.contains("\0"), !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw FinderReadError.noSuchItem
        }
    }
}

public enum FinderReadError: Error, Equatable {
    case noSuchItem, versionChanged, anchorExpired, outsideRoot, disabled, timedOut, unsupportedNames
}
