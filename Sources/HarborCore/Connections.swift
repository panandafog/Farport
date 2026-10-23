import Foundation

public struct TerminalSize: Sendable {
    public var columns: Int
    public var rows: Int
    public init(columns: Int = 100, rows: Int = 30) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }
}

public protocol TerminalSession: AnyObject, Sendable {
    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws
    func send(_ data: Data) async throws
    func resize(_ size: TerminalSize) async throws
    func checkConnection(timeout: TimeInterval) async throws
    func close() async
}

public struct RemoteEntry: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable { case file, directory, symbolicLink }
    public let path: String
    public let name: String
    public let kind: Kind
    public let size: UInt64?
    public let modified: Date?
    public var id: String { path }

    public init(path: String, name: String, kind: Kind, size: UInt64?, modified: Date?) {
        self.path = path; self.name = name; self.kind = kind; self.size = size; self.modified = modified
    }
}

public typealias TransferProgress = @Sendable (_ completed: UInt64, _ total: UInt64) async -> Void

// File transport and terminal transport are independent capabilities, not a single SSH-shaped interface.
public protocol RemoteFileSession: AnyObject, Sendable {
    func canonicalPath(_ path: String) async throws -> String
    func list(_ path: String) async throws -> [RemoteEntry]
    func createDirectory(_ path: String) async throws
    func rename(_ path: String, to destination: String) async throws
    func remove(_ entry: RemoteEntry) async throws
    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) async throws
    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) async throws
    func close() async
}

public protocol ConnectionProvider: Sendable {
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession
    func files(for host: SavedHost) async throws -> any RemoteFileSession
    func waitForAccess(for host: SavedHost) async -> Bool
}

public extension ConnectionProvider {
    // Foreground callers may wait after an access failure, then retry the original request once.
    func waitForAccess(for host: SavedHost) async -> Bool { false }

    func terminal(for host: SavedHost) async throws -> any TerminalSession {
        try await terminal(for: host, sessionID: host.id)
    }
}

public enum RemotePath {
    public static func appending(_ name: String, to directory: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw HarborError.message("Use a file name without slashes, '.' or '..'.")
        }
        return (directory == "/" ? "" : directory) + "/" + name
    }

    public static func parent(of path: String) -> String {
        let components = path.split(separator: "/").dropLast()
        return "/" + components.joined(separator: "/")
    }
}
