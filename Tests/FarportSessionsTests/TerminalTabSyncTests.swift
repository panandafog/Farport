import FarportCloud
import FarportCore
import FarportSessions
import XCTest

@MainActor
final class TerminalTabSyncTests: XCTestCase {
    func testCloudModelPublishesTabEditsAndAppliesThemInBothDirections() async throws {
        let original = host()
        let (firstStream, firstUpdates) = AsyncStream<HostSyncSnapshot>.makeStream()
        let (secondStream, secondUpdates) = AsyncStream<HostSyncSnapshot>.makeStream()
        let firstService = TabSyncService(updates: firstUpdates)
        let secondService = TabSyncService(updates: secondUpdates)
        let firstCloud = CloudSyncModel(service: firstService, updates: firstStream)
        let secondCloud = CloudSyncModel(service: secondService, updates: secondStream)
        let desktop = TabSyncDevice(hosts: [original], cloud: firstCloud)
        let mobile = TabSyncDevice(hosts: [original], cloud: secondCloud)
        try await wait { firstCloud.snapshot.initialized && secondCloud.snapshot.initialized }
        let first = try XCTUnwrap(desktop.library.selectedWorkspace)
        let second = try XCTUnwrap(mobile.library.selectedWorkspace)
        _ = first.addTerminal()
        _ = first.addTerminal()
        try await wait { firstCloud.snapshot.profiles.first?.terminalTabs?.tabs.count == 3 }
        try await secondService.merge(firstService.records())
        try await wait { second.tabs.count == 3 }
        XCTAssertEqual(second.tabs, first.tabs)
        XCTAssertEqual(second.selectedTerminalID, original.id)
        _ = second.addTerminal()
        try await wait { secondCloud.snapshot.profiles.first?.terminalTabs?.tabs.count == 4 }
        try await firstService.merge(secondService.records())
        try await wait { first.tabs.count == 4 }
        XCTAssertEqual(first.tabs, second.tabs)
        XCTAssertEqual(first.selectedTerminalID, first.tabs[2].id)
        firstUpdates.finish()
        secondUpdates.finish()
        desktop.library.closeAll()
        mobile.library.closeAll()
    }

    func testThreeLegacyDesktopTabsReachMobileAndKeepSelectionCredentialsAndModeLocal() throws {
        let host = SavedHost(profile: HostProfile(hostname: "sync.invalid", username: "test",
                                                  terminalResumeStrategy: .tmux),
                             credentials: HostCredentials(password: "desktop-secret"))
        var legacy = HostWorkspace(hostID: host.id)
        legacy.terminals += [TerminalTab(title: "Logs"), TerminalTab(title: "Build")]
        legacy.selectedTerminalID = legacy.terminals.last?.id
        legacy.mode = .files
        let desktop = TabSyncDevice(hosts: [host], saved: WorkspaceSnapshot(hosts: [legacy]))
        var mobileHost = host
        mobileHost.credentials = HostCredentials()
        mobileHost.credentialsConfigured = false
        let mobile = TabSyncDevice(hosts: [mobileHost])
        var cloud = ProfileSyncLedger()
        try cloud.bootstrap(desktop.library.hosts.map(\.profile))
        var phone = ProfileSyncLedger()
        for record in cloud.records.values { try phone.merge(record) }
        try phone.bootstrap(mobile.library.hosts.map(\.profile))
        try mobile.library.applySyncedProfiles(phone.profiles)
        let workspace = try XCTUnwrap(mobile.library.selectedWorkspace)
        XCTAssertEqual(workspace.tabs, legacy.terminals)
        XCTAssertEqual(workspace.selectedTerminalID, host.id)
        XCTAssertEqual(workspace.mode, .terminal)
        XCTAssertEqual(workspace.terminal?.state, .disconnected)
        XCTAssertEqual(workspace.tabs.map(\.tmuxSessionName), legacy.terminals.map(\.tmuxSessionName))
        XCTAssertEqual(mobile.library.hosts.first?.credentials.password, "")
        XCTAssertFalse(try XCTUnwrap(mobile.library.hosts.first).credentialsConfigured)
        XCTAssertEqual(desktop.library.selectedWorkspace?.mode, .files)
        XCTAssertEqual(desktop.library.selectedWorkspace?.selectedTerminalID, legacy.selectedTerminalID)
        let restarted = TabSyncDevice(hosts: mobile.hosts.hosts, saved: mobile.workspaces.snapshot)
        XCTAssertEqual(restarted.library.selectedWorkspace?.tabs, legacy.terminals)
    }

    func testIncomingTabRenameAndAddKeepAnActiveTerminalAndItsOutput() async throws {
        let device = TabSyncDevice(hosts: [host()])
        let workspace = try XCTUnwrap(device.library.selectedWorkspace)
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.screen.write(Data("retained output".utf8))
        terminal.connect()
        try await wait { terminal.state == .connected }
        let output = terminal.screen.data
        var remote = try XCTUnwrap(device.library.hosts.first?.profile)
        var tabs = workspace.tabs
        tabs[0].title = "Renamed on desktop"
        tabs.append(TerminalTab(title: "Logs"))
        var layout = SyncedTerminalTabs()
        try layout.record(tabs, device: UUID())
        remote.terminalTabs = layout
        XCTAssertTrue(device.library.canApplySyncedProfiles([remote]))
        try device.library.applySyncedProfiles([remote])
        XCTAssertEqual(workspace.tabs, tabs)
        XCTAssertTrue(workspace.terminal === terminal)
        XCTAssertEqual(terminal.state, .connected)
        XCTAssertEqual(terminal.screen.data, output)
        device.library.closeAll()
    }

    func testRemoteCloseOfActiveTabWaitsForConfirmationAndNeverStartsAnotherConnection() async throws {
        let device = TabSyncDevice(hosts: [host()])
        let workspace = try XCTUnwrap(device.library.selectedWorkspace)
        _ = workspace.addTerminal()
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.connect()
        try await wait { terminal.state == .connected }
        var remote = try XCTUnwrap(device.library.hosts.first?.profile)
        try remote.terminalTabs?.record([], device: UUID())
        XCTAssertFalse(device.library.canApplySyncedProfiles([remote]))
        XCTAssertEqual(terminal.state, .connected)
        try device.library.applySyncedProfiles([remote])
        XCTAssertTrue(workspace.tabs.isEmpty)
        XCTAssertNil(workspace.terminal)
        XCTAssertEqual(terminal.state, .disconnected)
        let restarted = TabSyncDevice(hosts: device.hosts.hosts, saved: device.workspaces.snapshot)
        XCTAssertTrue(try XCTUnwrap(restarted.library.selectedWorkspace).tabs.isEmpty)
    }

    func testStaleHostEditorCannotReplaceNewTabsAndSelectionDoesNotChangeRevisions() throws {
        let original = host()
        let device = TabSyncDevice(hosts: [original])
        let workspace = try XCTUnwrap(device.library.selectedWorkspace)
        let extra = workspace.addTerminal()
        var stale = original
        stale.profile.notes = "Settings edited while another tab was created"
        try device.library.save(stale)
        XCTAssertEqual(workspace.tabs.count, 2)
        let layout = device.library.hosts.first?.profile.terminalTabs
        workspace.selectedTerminalID = original.id
        workspace.selectedTerminalID = extra
        workspace.mode = .files
        XCTAssertEqual(device.library.hosts.first?.profile.terminalTabs, layout)
    }

    func testWorkspaceWriteFailureCannotLoseDefinitionsAlreadySavedInHostLibrary() throws {
        let device = TabSyncDevice(hosts: [host()])
        let workspace = try XCTUnwrap(device.library.selectedWorkspace)
        device.workspaces.failWrites = true
        let extra = workspace.addTerminal()
        XCTAssertNotNil(device.library.error)
        let restarted = TabSyncDevice(hosts: device.hosts.hosts, saved: device.workspaces.snapshot)
        XCTAssertTrue(try XCTUnwrap(restarted.library.selectedWorkspace).tabs.contains { $0.id == extra })
    }

    func testDuplicateCrossHostTabIdentitiesAreRejectedBeforeWriting() throws {
        let first = host()
        let second = host()
        let device = TabSyncDevice(hosts: [first, second])
        var layout = SyncedTerminalTabs()
        try layout.record([TerminalTab(id: first.id, title: "Shell")], device: UUID())
        var profiles = device.library.hosts.map(\.profile)
        profiles[1].terminalTabs = layout
        let before = device.hosts.hosts
        XCTAssertThrowsError(try device.library.applySyncedProfiles(profiles))
        XCTAssertEqual(device.hosts.hosts, before)
    }

    private func host() -> SavedHost {
        SavedHost(profile: HostProfile(hostname: "sync.invalid", username: "test"))
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Terminal did not connect")
    }
}

@MainActor
private final class TabSyncDevice {
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

private actor TabSyncService: HostSyncService {
    private var ledger = ProfileSyncLedger()
    private let updates: AsyncStream<HostSyncSnapshot>.Continuation

    init(updates: AsyncStream<HostSyncSnapshot>.Continuation) { self.updates = updates }
    func records() -> [CloudHostRecord] { Array(ledger.records.values) }
    func merge(_ records: [CloudHostRecord]) throws {
        for record in records { try ledger.merge(record) }
        publish()
    }
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
                                       baseline: Array(ledger.baseline.values)))
    }
}

private final class TabSyncHosts: HostRepository {
    var hosts: [SavedHost]
    init(_ hosts: [SavedHost]) { self.hosts = hosts }
    func load() -> [SavedHost] { hosts }
    func save(_ hosts: [SavedHost]) { self.hosts = hosts }
}

private final class TabSyncWorkspaces: WorkspaceRepository {
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

private struct TabSyncProvider: ConnectionProvider {
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession { TabSyncSession() }
    func files(for host: SavedHost) async throws -> any RemoteFileSession { throw CancellationError() }
}

private actor TabSyncSession: TerminalSession {
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
