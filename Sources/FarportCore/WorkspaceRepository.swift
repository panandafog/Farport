import FarportLocalization
import Foundation

public enum WorkspaceMode: String, Codable, CaseIterable, Sendable {
    case terminal = "Terminal"
    case files = "Files"
}

public struct TerminalTab: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }

    public var tmuxSessionName: String { "harbor-" + id.uuidString.lowercased() }
}

public struct HostWorkspace: Codable, Equatable, Sendable {
    public var hostID: UUID
    public var terminals: [TerminalTab]
    public var selectedTerminalID: UUID?
    public var mode: WorkspaceMode

    public init(hostID: UUID) {
        self.hostID = hostID
        // Reuse the pre-tabs tmux identity for the first terminal on an existing host.
        terminals = [TerminalTab(id: hostID, title: L10n.text("Terminal %lld", 1))]
        selectedTerminalID = hostID
        mode = .terminal
    }
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var selectedHostID: UUID?
    public var hosts: [HostWorkspace]

    public init(selectedHostID: UUID? = nil, hosts: [HostWorkspace] = []) {
        self.selectedHostID = selectedHostID
        self.hosts = hosts
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw HarborError.message(L10n.text("This workspace was saved by a newer version of Farport."))
        }
        let tabs = hosts.flatMap(\.terminals)
        guard Set(hosts.map(\.hostID)).count == hosts.count,
              Set(tabs.map(\.id)).count == tabs.count,
              tabs.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              hosts.allSatisfy({ host in
                  if let selected = host.selectedTerminalID { return host.terminals.contains { $0.id == selected } }
                  return host.terminals.isEmpty
              }) else {
            throw HarborError.message(L10n.text("The saved workspace contains invalid or duplicate tabs."))
        }
    }
}

public protocol WorkspaceRepository {
    func load() throws -> WorkspaceSnapshot
    func save(_ snapshot: WorkspaceSnapshot) throws
}

public struct JSONWorkspaceRepository: WorkspaceRepository {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> WorkspaceSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return WorkspaceSnapshot() }
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(contentsOf: url))
        try snapshot.validate()
        return snapshot
    }

    public func save(_ snapshot: WorkspaceSnapshot) throws {
        try snapshot.validate()
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
