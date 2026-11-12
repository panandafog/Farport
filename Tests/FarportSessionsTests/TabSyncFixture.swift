import FarportCloud
import FarportCore
import FarportSessions
import XCTest

@MainActor
final class TabSyncDevice {
    let hosts: TabSyncHosts
    let workspaces: TabSyncWorkspaces
    let library: HostLibraryModel<RecordingTerminal>

    init(hosts: [SavedHost], saved: WorkspaceSnapshot = WorkspaceSnapshot(), cloud: CloudSyncModel? = nil) {
        self.hosts = TabSyncHosts(hosts)
        workspaces = TabSyncWorkspaces(saved)
        library = HostLibraryModel(repository: self.hosts, workspaceRepository: workspaces,
                                   cloud: cloud,
                                   makeProvider: { _ in TabSyncProvider() }, makeTerminal: {
            RecordingTerminal(host: $0, provider: $1, sessionID: $2, trust: $3)
        })
    }
}

actor TabSyncService: HostSyncService {
    private var ledger = ProfileSyncLedger()
    private let updates: AsyncStream<HostSyncSnapshot>.Continuation

    init(updates: AsyncStream<HostSyncSnapshot>.Continuation) { self.updates = updates }
    func records() -> [CloudHostRecord] { Array(ledger.records.values) }
    func merge(_ records: [CloudHostRecord]) throws {
        for record in records { try ledger.merge(record) }
        publish()
    }
    func delete(_ id: UUID) throws { try ledger.serverDeleted(id); publish() }
    func resume(profiles: [HostProfile]) {
        do { try ledger.bootstrap(profiles); publish() } catch { XCTFail(error.localizedDescription) }
    }
    func enable(profiles: [HostProfile]) { resume(profiles: profiles) }
    func disable() {}
    func refresh(profiles: [HostProfile]) throws { try localChanged(profiles: profiles) }
    func localChanged(profiles: [HostProfile]) throws { try ledger.localChanged(profiles); publish() }
    func applied(profiles: [HostProfile]) throws { try ledger.applied(profiles); publish() }
    func dismissConflict(_ id: String) {}
    private func publish() {
        updates.yield(HostSyncSnapshot(enabled: true, initialized: true, profiles: ledger.profiles,
                                       baseline: Array(ledger.baseline.values),
                                       deletedHostIDs: Set(ledger.records.values.filter(\.deleted).map(\.id))))
    }
}

final class TabSyncHosts: HostRepository {
    var hosts: [SavedHost]
    init(_ hosts: [SavedHost]) { self.hosts = hosts }
    func load() -> [SavedHost] { hosts }
    func save(_ hosts: [SavedHost]) { self.hosts = hosts }
}

final class TabSyncWorkspaces: WorkspaceRepository {
    var snapshot: WorkspaceSnapshot
    var failWrites = false
    init(_ snapshot: WorkspaceSnapshot) { self.snapshot = snapshot }
    func load() -> WorkspaceSnapshot { snapshot }
    func save(_ snapshot: WorkspaceSnapshot) throws {
        if failWrites { throw HarborError.message("Test workspace write failure") }
        try snapshot.validate()
        self.snapshot = snapshot
    }
}

struct TabSyncProvider: ConnectionProvider {
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession { TabSyncSession() }
    func files(for host: SavedHost) async throws -> any RemoteFileSession { throw CancellationError() }
}

actor TabSyncSession: TerminalSession {
    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        try await Task.sleep(for: .seconds(60))
    }
    func send(_ data: Data) {}
    func resize(_ size: TerminalSize) {}
    func checkConnection(timeout: TimeInterval) {}
    func close() {}
}
