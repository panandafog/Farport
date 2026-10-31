import FarportLocalization
import Foundation

public struct ProfileSyncLedger: Codable, Sendable {
    public let deviceID: UUID
    public private(set) var counter: UInt64 = 0
    public private(set) var records: [UUID: CloudHostRecord] = [:]
    public private(set) var pending: Set<UUID> = []
    public private(set) var baseline: [UUID: HostProfile] = [:]
    public private(set) var conflicts: [CloudProfileConflict] = []
    public var profiles: [HostProfile] {
        records.values.compactMap(\.profile).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public init(deviceID: UUID = UUID()) { self.deviceID = deviceID }

    public func validate() throws {
        guard pending.isSubset(of: Set(records.keys)), conflicts.count <= 50,
              Set(conflicts.map(\.id)).count == conflicts.count else {
            throw HarborError.message(L10n.text("Inconsistent iCloud sync index."))
        }
        for (id, record) in records {
            try record.validate()
            guard id == record.id, counter >= record.revision.counter else {
                throw HarborError.message(L10n.text("Inconsistent iCloud host revision."))
            }
        }
        for (id, profile) in baseline {
            try profile.validate()
            guard id == profile.id else {
                throw HarborError.message(L10n.text("Inconsistent iCloud profile baseline."))
            }
        }
        for conflict in conflicts {
            try conflict.record.validate()
            guard conflict.profile != nil, counter >= conflict.record.revision.counter else {
                throw HarborError.message(L10n.text("Inconsistent iCloud recovery copy."))
            }
        }
    }

    // Cloud settings win over unversioned local settings. Independently versioned tab definitions still merge.
    public mutating func bootstrap(_ local: [HostProfile]) throws {
        let values = try indexed(local)
        for profile in local {
            if let remote = records[profile.id] {
                if remote.profile?.hasSameSettings(as: profile) != true {
                    archive(CloudHostRecord(id: profile.id, revision: try nextRevision(), profile: profile))
                }
                if let cloud = remote.profile {
                    let merged = try cloud.mergingTerminalTabs(from: profile)
                    if merged != cloud { try edit(profile.id, profile: merged) }
                }
            } else { try edit(profile.id, profile: profile) }
        }
        baseline = values
    }

    public mutating func localChanged(_ local: [HostProfile]) throws {
        let values = try indexed(local)
        for profile in local where baseline[profile.id] != profile {
            if records[profile.id]?.deleted == true {
                archive(CloudHostRecord(id: profile.id, revision: try nextRevision(), profile: profile))
            } else {
                if let current = records[profile.id], let baseline = baseline[profile.id],
                   current.profile?.hasSameSettings(as: baseline) != true { archive(current) }
                let merged = try records[profile.id]?.profile.map {
                    try profile.mergingTerminalTabs(from: $0)
                } ?? profile
                try edit(profile.id, profile: merged)
            }
        }
        for id in baseline.keys where values[id] == nil { try edit(id, profile: nil) }
        baseline = values
    }

    public mutating func applied(_ profiles: [HostProfile]) throws { baseline = try indexed(profiles) }

    public mutating func merge(_ incoming: CloudHostRecord) throws {
        try incoming.validate()
        counter = max(counter, incoming.revision.counter)
        guard let current = records[incoming.id] else {
            records[incoming.id] = incoming
            return
        }
        guard current != incoming else { pending.remove(incoming.id); return }
        guard current.revision != incoming.revision else {
            throw HarborError.message(L10n.text(
                "An iCloud host revision contains inconsistent data. Sync was stopped."
            ))
        }
        let winner: CloudHostRecord
        if current.deleted != incoming.deleted { winner = current.deleted ? current : incoming } else {
            winner = current.revision > incoming.revision ? current : incoming
        }
        if !sameSettings(current.profile, incoming.profile), pending.contains(current.id) {
            archive(winner == current ? incoming : current)
        }
        if let profile = winner.profile, let other = (winner == current ? incoming : current).profile {
            let merged = try profile.mergingTerminalTabs(from: other)
            if merged != profile {
                records[incoming.id] = winner
                try edit(incoming.id, profile: merged)
                return
            }
        }
        records[incoming.id] = winner
        if winner == incoming { pending.remove(incoming.id) } else { pending.insert(incoming.id) }
    }

    public mutating func serverDeleted(_ id: UUID) throws {
        if let current = records[id] { archive(current) }
        try edit(id, profile: nil)
    }

    public mutating func acknowledge(_ record: CloudHostRecord) {
        if records[record.id] == record { pending.remove(record.id) }
    }

    public mutating func dismissConflict(_ id: String) { conflicts.removeAll { $0.id == id } }

    private mutating func edit(_ id: UUID, profile: HostProfile?) throws {
        if profile == nil, records[id]?.deleted == true { return }
        let value = CloudHostRecord(id: id, revision: try nextRevision(), parent: records[id]?.revision,
                                    profile: profile)
        try value.validate()
        records[id] = value
        pending.insert(id)
    }

    private mutating func nextRevision() throws -> ProfileRevision {
        guard counter < UInt64.max - 1 else {
            throw HarborError.message(L10n.text("The iCloud revision counter is exhausted."))
        }
        counter += 1
        return ProfileRevision(counter: counter, device: deviceID)
    }

    private mutating func archive(_ record: CloudHostRecord) {
        guard record.profile != nil else { return }
        let conflict = CloudProfileConflict(record: record)
        if !conflicts.contains(where: { $0.id == conflict.id }) { conflicts.append(conflict) }
        if conflicts.count > 50 { conflicts.removeFirst(conflicts.count - 50) }
    }

    private func indexed(_ profiles: [HostProfile]) throws -> [UUID: HostProfile] {
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw HarborError.message(L10n.text("Duplicate host IDs."))
        }
        try profiles.forEach { try $0.validate() }
        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    private func sameSettings(_ left: HostProfile?, _ right: HostProfile?) -> Bool {
        if let left, let right { return left.hasSameSettings(as: right) }
        return left == right
    }
}
