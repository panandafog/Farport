import FarportLocalization
import Foundation

public struct TerminalTabChange: Codable, Equatable, Sendable {
    public var tab: TerminalTab
    public var position: Int
    public var revision: ProfileRevision
    public var deleted: Bool
}

/// Only tab definitions travel between devices. Selection, connections and terminal output remain local.
public struct SyncedTerminalTabs: Codable, Equatable, Sendable {
    public private(set) var changes: [TerminalTabChange] = []

    public init() {}

    public var tabs: [TerminalTab] {
        changes.filter { !$0.deleted }.sorted {
            $0.position == $1.position ? $0.tab.id.uuidString < $1.tab.id.uuidString : $0.position < $1.position
        }.map(\.tab)
    }

    public func validate() throws {
        guard Set(changes.map { $0.tab.id }).count == changes.count,
              changes.allSatisfy({
                  !$0.tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      $0.position >= 0 && $0.position < Int.max &&
                      $0.revision.counter > 0 && $0.revision.counter < UInt64.max
              }) else {
            throw HarborError.message(L10n.text("The saved workspace contains invalid or duplicate tabs."))
        }
    }

    public mutating func record(_ tabs: [TerminalTab], device: UUID) throws {
        try validate()
        guard Set(tabs.map(\.id)).count == tabs.count else {
            throw HarborError.message(L10n.text("The saved workspace contains invalid or duplicate tabs."))
        }
        var updated = Dictionary(uniqueKeysWithValues: changes.map { ($0.tab.id, $0) })
        let counter = changes.map(\.revision.counter).max() ?? 0
        guard counter < UInt64.max - 1 else {
            throw HarborError.message(L10n.text("The iCloud revision counter is exhausted."))
        }
        let revision = ProfileRevision(counter: counter + 1, device: device)
        for (position, tab) in tabs.enumerated() {
            if let current = updated[tab.id], current.deleted { continue }
            if updated[tab.id]?.tab != tab || updated[tab.id]?.position != position {
                updated[tab.id] = TerminalTabChange(tab: tab, position: position, revision: revision, deleted: false)
            }
        }
        let ids = Set(tabs.map(\.id))
        for change in changes where !change.deleted && !ids.contains(change.tab.id) {
            var removed = change
            removed.deleted = true
            removed.revision = revision
            updated[change.tab.id] = removed
        }
        let result = Self(changes: Array(updated.values))
        try result.validate()
        self = result
    }

    public func merging(_ other: Self) throws -> Self {
        try validate()
        try other.validate()
        var merged = Dictionary(uniqueKeysWithValues: changes.map { ($0.tab.id, $0) })
        for change in other.changes {
            guard let current = merged[change.tab.id] else { merged[change.tab.id] = change; continue }
            guard current != change else { continue }
            if current.deleted != change.deleted {
                // Closed UUIDs never reopen; new tabs always receive a new UUID.
                merged[change.tab.id] = current.deleted ? current : change
            } else if current.revision != change.revision {
                merged[change.tab.id] = current.revision > change.revision ? current : change
            } else {
                throw HarborError.message(L10n.text(
                    "An iCloud host revision contains inconsistent data. Sync was stopped."
                ))
            }
        }
        return Self(changes: Array(merged.values))
    }

    public func copy(for hostID: UUID) throws -> Self {
        var copy = Self()
        let copied = tabs.enumerated().map { index, tab in
            TerminalTab(id: index == 0 ? hostID : UUID(), title: tab.title)
        }
        try copy.record(copied, device: UUID())
        return copy
    }

    private init(changes: [TerminalTabChange]) {
        self.changes = changes.sorted { $0.tab.id.uuidString < $1.tab.id.uuidString }
    }
}
