import CloudKit
import FarportCore
import Foundation

public struct HostSyncSnapshot: Sendable {
    public var enabled: Bool
    public var initialized: Bool
    public var profiles: [HostProfile]
    public var baseline: [HostProfile]
    public var pendingCount: Int
    public var conflicts: [CloudProfileConflict]
    public var status: String
    public var lastContact: Date?

    public init(enabled: Bool = false, initialized: Bool = false, profiles: [HostProfile] = [], pendingCount: Int = 0,
                conflicts: [CloudProfileConflict] = [], status: String = "Off", lastContact: Date? = nil,
                baseline: [HostProfile] = []) {
        self.enabled = enabled; self.initialized = initialized; self.profiles = profiles
        self.pendingCount = pendingCount; self.conflicts = conflicts; self.status = status
        self.lastContact = lastContact; self.baseline = baseline
    }
}

public protocol HostSyncService: Sendable {
    func resume(profiles: [HostProfile]) async
    func enable(profiles: [HostProfile]) async throws
    func disable() async throws
    func refresh(profiles: [HostProfile]) async throws
    func localChanged(profiles: [HostProfile]) async throws
    func applied(profiles: [HostProfile]) async throws
    func dismissConflict(_ id: String) async throws
}

struct CloudSyncDocument: Codable {
    var schemaVersion = 1
    var enabled = false
    var accountID: String?
    var resetRequired = false
    var initialized = false
    var ledger = ProfileSyncLedger()
    var engineState: CKSyncEngine.State.Serialization?
    var serverFields: [String: Data] = [:]
    var lastContact: Date?
    var pauseReason: String?
}

struct CloudSyncFile {
    let url: URL
    func load() throws -> CloudSyncDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return CloudSyncDocument() }
        let value = try JSONDecoder().decode(CloudSyncDocument.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw HarborError.message("Unsupported iCloud sync index.") }
        try value.ledger.validate()
        return value
    }
    func save(_ value: CloudSyncDocument) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
