import Foundation
import HarborCore

@MainActor
final class FilesModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var entries: [RemoteEntry] = []
    @Published private(set) var path = ""
    @Published var pathInput = ""
    @Published var selection: String?
    @Published var error: String?
    @Published private(set) var requirement: ConnectionRequirement?
    @Published private(set) var waitingForAccess = false
    @Published private(set) var activity = ""
    @Published private(set) var progress: Double?
    @Published private(set) var transferred: UInt64 = 0
    @Published private(set) var total: UInt64 = 0
    @Published var showHidden = false
    private var host: SavedHost
    private var provider: any ConnectionProvider
    private var session: (any RemoteFileSession)?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var operationID = UUID()
    private let trust: ServerTrustModel?

    init(host: SavedHost, provider: any ConnectionProvider, trust: ServerTrustModel? = nil) {
        self.host = host; self.provider = provider
        self.trust = trust
    }

    var visibleEntries: [RemoteEntry] { entries.filter { showHidden || !$0.name.hasPrefix(".") } }
    var selectedEntry: RemoteEntry? { entries.first { $0.id == selection } }

    func reconfigure(host: SavedHost, provider: any ConnectionProvider) {
        disconnect()
        self.host = host
        self.provider = provider
    }

    func connect() {
        guard !busy, !connected else { return }
        busy = true
        activity = "Connecting"
        error = nil
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
                activity = "Connected"
            } catch {
                guard generation == token else { return }
                await session?.close()
                guard generation == token else { return }
                session = nil
                if Task.isCancelled {
                    activity = "Cancelled"
                } else {
                    requirement = ConnectionRequirement(error)
                    self.error = requirement == nil ? error.localizedDescription : nil
                    activity = requirement?.title ?? "Connection failed"
                }
            }
            if generation == token { busy = false; waitingForAccess = false }
            if case .serverKey = requirement { reviewRequirement() }
        }
    }

    func navigate(_ directory: String) {
        perform("Loading folder") { connection in
            let canonical = try await connection.canonicalPath(directory)
            let items = try await connection.list(canonical)
            try Task.checkCancellation()
            self.path = canonical; self.pathInput = canonical; self.entries = items; self.selection = nil
        }
    }

    func refresh() { navigate(path) }

    func reviewRequirement() {
        guard let requirement else { return }
        if case .serverKey(let key) = requirement {
            let token = generation
            trust?.present(key, retry: { [weak self] in
                guard let self, self.generation == token else { return }
                self.connect()
            })
        } else { connect() }
    }
    func home() { navigate(host.profile.initialDirectory.isEmpty ? "." : host.profile.initialDirectory) }
    func up() { navigate(RemotePath.parent(of: path)) }

    func createDirectory(_ name: String) {
        perform("Creating folder", refresh: true) { connection in
            try await connection.createDirectory(RemotePath.appending(name, to: self.path))
        }
    }

    func rename(_ entry: RemoteEntry, name: String) {
        perform("Renaming", refresh: true) { connection in
            try await connection.rename(entry.path, to: RemotePath.appending(name, to: self.path))
        }
    }

    func remove(_ entry: RemoteEntry) {
        perform("Deleting", refresh: true) { try await $0.remove(entry) }
    }

    func upload(_ urls: [URL]) {
        let directory = path
        perform("Uploading", refresh: true) { connection in
            for url in urls {
                try Task.checkCancellation()
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw HarborError.message("Select individual files. Folder upload is not included in this MVP.")
                }
                let destination = try RemotePath.appending(url.lastPathComponent, to: directory)
                let existing = try await connection.list(directory)
                guard !existing.contains(where: { $0.path == destination }) else {
                    throw HarborError.message("'\(url.lastPathComponent)' already exists. Rename it before uploading.")
                }
                self.activity = "Uploading \(url.lastPathComponent)"
                try await connection.upload(url, to: destination, progress: self.progressHandler())
            }
        }
    }

    func download(_ entry: RemoteEntry, to destination: URL) {
        perform("Downloading \(entry.name)") { connection in
            try await connection.download(entry.path, to: destination, progress: self.progressHandler())
        }
    }

    private func progressHandler() -> TransferProgress {
        let token = generation
        return { [weak self] completed, total in
            await self?.updateProgress(completed: completed, total: total, token: token)
        }
    }

    private func updateProgress(completed: UInt64, total: UInt64, token: UUID) {
        guard token == generation else { return }
        self.transferred = completed; self.total = total
        progress = total == 0 ? 1 : min(1, Double(completed) / Double(total))
    }

    private func perform(_ label: String, refresh: Bool = false,
                         operation: @escaping (any RemoteFileSession) async throws -> Void) {
        guard !busy, let session else { return }
        busy = true; activity = label; error = nil; progress = nil
        operationID = UUID()
        let token = generation
        task = Task {
            do {
                try await operation(session)
                try Task.checkCancellation()
                if refresh {
                    let items = try await session.list(path)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    entries = items; selection = nil
                }
                activity = "Completed"
            } catch {
                guard generation == token else { return }
                if Task.isCancelled {
                    activity = "Cancelled"
                } else {
                    self.error = error.localizedDescription
                    activity = "Failed"
                }
            }
            if generation == token { busy = false; progress = nil }
        }
    }

    func cancel() {
        if waitingForAccess { disconnect(); activity = "Cancelled"; return }
        guard busy else { return }
        task?.cancel()
        activity = "Cancelling"
        let operation = operationID
        let token = generation
        // Give transfers time to remove staging files, then unblock a stalled network read.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.busy, self.operationID == operation, self.generation == token else { return }
            self.disconnect()
            self.activity = "Cancelled"
        }
    }

    func disconnect() {
        requirement = nil
        waitingForAccess = false
        generation = UUID()
        task?.cancel()
        let previous = session
        session = nil
        connected = false; busy = false; progress = nil
        activity = "Disconnected"
        Task { await previous?.close() }
    }
}

extension FilesModel {
    private func openFiles(token: UUID) async throws -> any RemoteFileSession {
        do { return try await provider.files(for: host) } catch {
            guard token == generation, !Task.isCancelled,
                  (error as? TerminalConnectionError)?.requiresLocalNetworkPermission == true else { throw error }
            waitingForAccess = true
            activity = "Waiting for Local Network"
            let available = await provider.waitForAccess(for: host)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            waitingForAccess = false
            guard available else { throw error }
            activity = "Connecting"
            return try await provider.files(for: host)
        }
    }
}
