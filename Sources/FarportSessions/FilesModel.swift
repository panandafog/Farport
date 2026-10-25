import Combine
import FarportCore
import FarportLocalization
import Foundation

@MainActor
public final class FilesModel: ObservableObject {
    @Published public private(set) var connected = false
    @Published public private(set) var busy = false
    @Published public private(set) var entries: [RemoteEntry] = []
    @Published public private(set) var path = ""
    @Published public var pathInput = ""
    @Published public var selection: String?
    @Published public var error: String?
    @Published public private(set) var settingsHostID: UUID?
    @Published public private(set) var requirement: ConnectionRequirement?
    @Published public private(set) var waitingForAccess = false
    @Published public private(set) var activity = ""
    @Published public private(set) var progress: Double?
    @Published public private(set) var transferred: UInt64 = 0
    @Published public private(set) var total: UInt64 = 0
    @Published public var showHidden = false
    private var host: SavedHost
    private var provider: any ConnectionProvider
    private var session: (any RemoteFileSession)?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var operationID = UUID()
    private let trust: ServerTrustModel?

    private struct OperationToken {
        let connection: UUID
        let operation: UUID
    }

    public init(host: SavedHost, provider: any ConnectionProvider, trust: ServerTrustModel? = nil) {
        self.host = host; self.provider = provider
        self.trust = trust
    }

    public var visibleEntries: [RemoteEntry] { entries.filter { showHidden || !$0.name.hasPrefix(".") } }
    public var selectedEntry: RemoteEntry? { entries.first { $0.id == selection } }

    public func reconfigure(host: SavedHost, provider: any ConnectionProvider) {
        disconnect()
        error = nil
        settingsHostID = nil
        self.host = host
        self.provider = provider
    }

    public func connect() {
        guard !busy, !connected else { return }
        busy = true
        activity = L10n.text("Connecting")
        error = nil
        settingsHostID = nil
        requirement = nil
        let token = UUID()
        generation = token
        operationID = UUID()
        task = Task {
            do {
                let connection = try await openFiles(token: token)
                guard generation == token, !Task.isCancelled else { await connection.close(); return }
                session = connection
                let initial = host.profile.initialDirectory
                let directory = try await connection.canonicalPath(initial.isEmpty ? "." : initial)
                let items = try await connection.list(directory)
                guard generation == token, !Task.isCancelled else { await connection.close(); return }
                path = directory; pathInput = directory; entries = items
                connected = true
                activity = L10n.text("Connected")
            } catch {
                guard generation == token else { return }
                await session?.close()
                guard generation == token else { return }
                session = nil
                if Task.isCancelled {
                    activity = L10n.text("Cancelled")
                } else {
                    requirement = ConnectionRequirement(error)
                    self.error = requirement == nil ? error.localizedDescription : nil
                    settingsHostID = (error as? TerminalConnectionError)?.settingsHostID(fallback: host.id)
                    if requirement == nil, !(error is TerminalConnectionError) { settingsHostID = host.id }
                    activity = requirement?.title ?? L10n.text("Connection failed")
                }
            }
            if generation == token { busy = false; waitingForAccess = false }
            if case .serverKey = requirement { reviewRequirement() }
        }
    }

    public func navigate(_ directory: String) {
        perform(L10n.text("Loading folder")) { connection, token in
            let canonical = try await connection.canonicalPath(directory)
            let items = try await connection.list(canonical)
            try self.checkCurrent(token)
            self.path = canonical; self.pathInput = canonical; self.entries = items; self.selection = nil
        }
    }

    public func refresh() { navigate(path) }

    public func reviewRequirement() {
        guard let requirement else { return }
        if case .serverKey(let key) = requirement {
            let token = generation
            trust?.present(key, retry: { [weak self] in
                guard let self, self.generation == token else { return }
                self.connect()
            })
        } else { connect() }
    }
    public func home() { navigate(host.profile.initialDirectory.isEmpty ? "." : host.profile.initialDirectory) }
    public func up() { navigate(RemotePath.parent(of: path)) }

    public func createDirectory(_ name: String) {
        perform(L10n.text("Creating folder"), refresh: true) { connection, _ in
            try await connection.createDirectory(RemotePath.appending(name, to: self.path))
        }
    }

    public func rename(_ entry: RemoteEntry, name: String) {
        perform(L10n.text("Renaming"), refresh: true) { connection, _ in
            try await connection.rename(entry.path, to: RemotePath.appending(name, to: self.path))
        }
    }

    public func remove(_ entry: RemoteEntry) {
        perform(L10n.text("Deleting"), refresh: true) { connection, _ in try await connection.remove(entry) }
    }

    public func upload(_ urls: [URL]) {
        let directory = path
        perform(L10n.text("Uploading"), refresh: true) { connection, token in
            for url in urls {
                try self.checkCurrent(token)
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw HarborError.message(L10n.text(
                        "Select individual files. Folder upload is not included in this MVP."
                    ))
                }
                let destination = try RemotePath.appending(url.lastPathComponent, to: directory)
                let existing = try await connection.list(directory)
                try self.checkCurrent(token)
                guard !existing.contains(where: { $0.path == destination }) else {
                    throw HarborError.message(L10n.text(
                        "'%@' already exists. Rename it before uploading.", url.lastPathComponent
                    ))
                }
                self.activity = L10n.text("Uploading %@", url.lastPathComponent)
                try await connection.upload(url, to: destination, progress: self.progressHandler(token))
            }
        }
    }

    public func download(_ entry: RemoteEntry, to destination: URL) {
        perform(L10n.text("Downloading %@", entry.name)) { connection, token in
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            try await connection.download(entry.path, to: destination, progress: self.progressHandler(token))
        }
    }

    private func progressHandler(_ token: OperationToken) -> TransferProgress {
        return { [weak self] completed, total in
            await self?.updateProgress(completed: completed, total: total, token: token)
        }
    }

    private func updateProgress(completed: UInt64, total: UInt64, token: OperationToken) {
        guard isCurrent(token), busy else { return }
        self.transferred = completed; self.total = total
        progress = total == 0 ? 1 : min(1, Double(completed) / Double(total))
    }

    private func perform(_ label: String, refresh: Bool = false,
                         operation: @escaping (any RemoteFileSession, OperationToken) async throws -> Void) {
        guard !busy, let session else { return }
        busy = true; activity = label; error = nil; progress = nil
        settingsHostID = nil
        operationID = UUID()
        transferred = 0
        total = 0
        let token = OperationToken(connection: generation, operation: operationID)
        task = Task {
            do {
                try await operation(session, token)
                try checkCurrent(token)
                if refresh {
                    let items = try await session.list(path)
                    try checkCurrent(token)
                    entries = items; selection = nil
                }
                activity = L10n.text("Completed")
            } catch {
                guard isCurrent(token) else { return }
                if Task.isCancelled {
                    activity = L10n.text("Cancelled")
                } else {
                    self.error = error.localizedDescription
                    settingsHostID = (error as? TerminalConnectionError)?.settingsHostID(fallback: host.id)
                    activity = L10n.text("Failed")
                    if error is TerminalConnectionError {
                        self.session = nil
                        connected = false
                        activity = L10n.text("Disconnected")
                        Task { await session.close() }
                    }
                }
            }
            if isCurrent(token) { busy = false; progress = nil }
        }
    }

    private func isCurrent(_ token: OperationToken) -> Bool {
        token.connection == generation && token.operation == operationID
    }

    private func checkCurrent(_ token: OperationToken) throws {
        try Task.checkCancellation()
        guard isCurrent(token) else { throw CancellationError() }
    }

    public func cancel() {
        if waitingForAccess { disconnect(); activity = L10n.text("Cancelled"); return }
        guard busy else { return }
        task?.cancel()
        activity = L10n.text("Cancelling")
        let operation = operationID
        let token = generation
        // Give transfers time to remove staging files, then unblock a stalled network read.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.busy, self.operationID == operation, self.generation == token else { return }
            self.disconnect()
            self.activity = L10n.text("Cancelled")
        }
    }

    public func disconnect() {
        requirement = nil
        waitingForAccess = false
        generation = UUID()
        task?.cancel()
        let previous = session
        session = nil
        connected = false; busy = false; progress = nil
        activity = L10n.text("Disconnected")
        Task { await previous?.close() }
    }
}

extension FilesModel {
    private func openFiles(token: UUID) async throws -> any RemoteFileSession {
        do { return try await provider.files(for: host) } catch {
            guard token == generation, !Task.isCancelled,
                  (error as? TerminalConnectionError)?.requiresLocalNetworkPermission == true else { throw error }
            waitingForAccess = true
            activity = L10n.text("Waiting for Local Network")
            let available = await provider.waitForAccess(for: host)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            waitingForAccess = false
            guard available else { throw error }
            activity = L10n.text("Connecting")
            return try await provider.files(for: host)
        }
    }
}
