import Foundation

/// The tab UUID remains the durable identity; server names can migrate without changing saved workspaces.
public struct TmuxSessionIdentity: Sendable {
    public let id: UUID
    public var name: String { "farport-" + id.uuidString.lowercased() }
    public var legacyName: String { "harbor-" + id.uuidString.lowercased() }

    public init(id: UUID) { self.id = id }
}
