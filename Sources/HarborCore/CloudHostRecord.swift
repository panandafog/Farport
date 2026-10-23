import Foundation

public struct ProfileRevision: Codable, Equatable, Comparable, Sendable {
    public let counter: UInt64
    public let device: UUID
    public init(counter: UInt64, device: UUID) { self.counter = counter; self.device = device }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.device.uuidString < rhs.device.uuidString : lhs.counter < rhs.counter
    }
}

public struct CloudHostRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let revision: ProfileRevision
    public let parent: ProfileRevision?
    public let profile: HostProfile?
    public var deleted: Bool { profile == nil }

    public init(id: UUID, revision: ProfileRevision, parent: ProfileRevision? = nil, profile: HostProfile?) {
        schemaVersion = 1; self.id = id; self.revision = revision; self.parent = parent; self.profile = profile
    }

    public func validate() throws {
        guard schemaVersion == 1, revision.counter > 0, revision.counter < UInt64.max,
              profile == nil || profile?.id == id else { throw HarborError.message("Unsupported iCloud host record.") }
        try profile?.validate()
        guard try JSONEncoder().encode(self).count <= 256 * 1024 else {
            throw HarborError.message("A host profile exceeds the 256 KB iCloud limit.")
        }
    }
}

public struct CloudProfileConflict: Codable, Identifiable, Equatable, Sendable {
    public let record: CloudHostRecord
    public var id: String { record.id.uuidString + ".\(record.revision.counter)." + record.revision.device.uuidString }
    public var profile: HostProfile? { record.profile }
    public init(record: CloudHostRecord) { self.record = record }
}
