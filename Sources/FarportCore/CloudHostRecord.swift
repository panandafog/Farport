import FarportLocalization
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
    public let settingsRevision: ProfileRevision?
    public let profile: HostProfile?
    public var deleted: Bool { profile == nil }

    public init(id: UUID, revision: ProfileRevision, parent: ProfileRevision? = nil, profile: HostProfile?,
                settingsRevision: ProfileRevision? = nil) {
        if profile?.terminalTabs?.hasSessionModes == true { schemaVersion = 4 } else {
            schemaVersion = profile?.position != nil || settingsRevision != nil ? 3 :
                (profile?.terminalTabs == nil ? 1 : 2)
        }
        self.id = id; self.revision = revision; self.parent = parent; self.profile = profile
        self.settingsRevision = settingsRevision
    }

    public func validate() throws {
        guard schemaVersion == 4 || profile?.terminalTabs?.hasSessionModes != true else {
            throw HarborError.message(L10n.text("Unsupported iCloud host record."))
        }
        guard (schemaVersion == 1 && profile?.terminalTabs == nil && profile?.position == nil &&
               settingsRevision == nil) ||
                (schemaVersion == 2 && profile?.position == nil && settingsRevision == nil) ||
                schemaVersion == 3 || schemaVersion == 4 else {
            throw HarborError.message(L10n.text("Unsupported iCloud host record."))
        }
        guard revision.counter > 0, revision.counter < UInt64.max,
              profile == nil || profile?.id == id else {
                  throw HarborError.message(L10n.text("Unsupported iCloud host record."))
              }
        try profile?.validate()
        if let settingsRevision {
            guard settingsRevision.counter > 0, settingsRevision <= revision else {
                throw HarborError.message(L10n.text("Inconsistent iCloud host revision."))
            }
        }
        guard try JSONEncoder().encode(self).count <= 256 * 1024 else {
            throw HarborError.message(L10n.text("A host profile exceeds the 256 KB iCloud limit."))
        }
    }
}

public struct CloudProfileConflict: Codable, Identifiable, Equatable, Sendable {
    public let record: CloudHostRecord
    public var id: String { record.id.uuidString + ".\(record.revision.counter)." + record.revision.device.uuidString }
    public var profile: HostProfile? { record.profile }
    public init(record: CloudHostRecord) { self.record = record }
}
