import Foundation

public struct ConnectionRoute: Sendable {
    /// Ordered SSH endpoints, including the final destination. Credentials never move between endpoints.
    public let hosts: [SavedHost]

    public init(to target: SavedHost, library: [SavedHost]) throws {
        let grouped = Dictionary(grouping: library, by: \.id)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else {
            throw TerminalConnectionError.configuration("The host library contains duplicate identifiers.")
        }
        var catalog = grouped.compactMapValues(\.first)
        catalog[target.id] = target
        var resolved: [SavedHost] = []
        try Self.append(target, catalog: catalog, path: [], resolved: &resolved)
        hosts = resolved
    }

    private static func append(_ host: SavedHost, catalog: [UUID: SavedHost], path: Set<UUID>,
                               resolved: inout [SavedHost]) throws {
        guard !path.contains(host.id), !resolved.contains(where: { $0.id == host.id }) else {
            throw TerminalConnectionError.configuration("ProxyJump route contains a cycle or repeated host.")
        }
        guard path.count < 8, resolved.count < 8 else {
            throw TerminalConnectionError.configuration("ProxyJump supports at most eight SSH endpoints.")
        }
        var path = path
        path.insert(host.id)
        for id in host.profile.jumpHostIDs {
            guard let jump = catalog[id] else {
                throw TerminalConnectionError.configuration(
                    "Jump host \(id.uuidString) for '\(host.profile.displayName)' is missing. " +
                    "Edit its connection route."
                )
            }
            guard jump.profile.terminalProvider == "ssh" else {
                throw TerminalConnectionError.configuration("Jump host '\(jump.profile.displayName)' must support SSH.")
            }
            try append(jump, catalog: catalog, path: path, resolved: &resolved)
        }
        guard resolved.count < 8 else {
            throw TerminalConnectionError.configuration("ProxyJump supports at most eight SSH endpoints.")
        }
        resolved.append(host)
    }

    public static func depends(_ host: SavedHost, on id: UUID, library: [SavedHost]) -> Bool {
        var pending = host.profile.jumpHostIDs
        var visited: Set<UUID> = []
        while let next = pending.popLast() {
            if next == id { return true }
            if visited.insert(next).inserted, let jump = library.first(where: { $0.id == next }) {
                pending.append(contentsOf: jump.profile.jumpHostIDs)
            }
        }
        return false
    }
}
