import FarportLocalization
import Foundation

public struct HostPosition: Codable, Equatable, Sendable {
    public let index: Int
    public let revision: ProfileRevision

    public init(index: Int, revision: ProfileRevision) { self.index = index; self.revision = revision }

    public func validate() throws {
        guard index >= 0, index < Int.max, revision.counter > 0, revision.counter < UInt64.max else {
            throw HarborError.message(L10n.text("Invalid saved host order."))
        }
    }
}

public enum HostOrdering {
    public static func sorted(_ profiles: [HostProfile]) -> [HostProfile] {
        profiles.sorted {
            let left = $0.position?.index ?? Int.max
            let right = $1.position?.index ?? Int.max
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }

    public static func record(_ hosts: [SavedHost], device: UUID) throws -> [SavedHost] {
        guard hosts.enumerated().contains(where: { $0.element.profile.position?.index != $0.offset }) else {
            return hosts
        }
        let counter = hosts.compactMap { $0.profile.position?.revision.counter }.max() ?? 0
        guard counter < UInt64.max - 1 else {
            throw HarborError.message(L10n.text("The iCloud revision counter is exhausted."))
        }
        let revision = ProfileRevision(counter: counter + 1, device: device)
        return hosts.enumerated().map { index, original in
            var host = original
            if host.profile.position?.index != index {
                host.profile.position = HostPosition(index: index, revision: revision)
            }
            return host
        }
    }
}

/// Foundation-only equivalent of the native list move operation, shared by both UIs.
public enum ItemOrdering {
    public static func moving<Element>(_ items: [Element], from offsets: IndexSet, to destination: Int) -> [Element] {
        guard (0...items.count).contains(destination), offsets.allSatisfy(items.indices.contains) else { return items }
        let moved = offsets.map { items[$0] }
        var result = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        result.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
        return result
    }

}
