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
        let migrated = legacy.terminals.map { $0.fillingMissingResumeStrategy(with: .tmux) }
        XCTAssertEqual(workspace.tabs, migrated)
        XCTAssertEqual(workspace.selectedTerminalID, host.id)
        XCTAssertEqual(workspace.mode, .terminal)
        XCTAssertEqual(workspace.terminal?.state, .disconnected)
        XCTAssertEqual(workspace.tabs.map(\.tmuxSessionName), legacy.terminals.map(\.tmuxSessionName))
        XCTAssertEqual(mobile.library.hosts.first?.credentials.password, "")
        XCTAssertFalse(try XCTUnwrap(mobile.library.hosts.first).credentialsConfigured)
        XCTAssertEqual(desktop.library.selectedWorkspace?.mode, .files)
        XCTAssertEqual(desktop.library.selectedWorkspace?.selectedTerminalID, legacy.selectedTerminalID)
        let restarted = TabSyncDevice(hosts: mobile.hosts.hosts, saved: mobile.workspaces.snapshot)
        XCTAssertEqual(restarted.library.selectedWorkspace?.tabs, migrated)
    }

    func testHostAndTabOrderReachAnotherDeviceWithoutReplacingTerminals() async throws {
        let hosts = (0..<3).map { SavedHost(profile: HostProfile(hostname: "host\($0).invalid", username: "test")) }
        let (firstStream, firstUpdates) = AsyncStream<HostSyncSnapshot>.makeStream()
        let (secondStream, secondUpdates) = AsyncStream<HostSyncSnapshot>.makeStream()
        defer { firstUpdates.finish(); secondUpdates.finish() }
        let firstService = TabSyncService(updates: firstUpdates)
        let secondService = TabSyncService(updates: secondUpdates)
        let firstCloud = CloudSyncModel(service: firstService, updates: firstStream)
        let secondCloud = CloudSyncModel(service: secondService, updates: secondStream)
        let desktop = TabSyncDevice(hosts: hosts, cloud: firstCloud)
        let mobile = TabSyncDevice(hosts: hosts, cloud: secondCloud)
        try await wait { firstCloud.snapshot.initialized && secondCloud.snapshot.initialized }
        let workspace = try XCTUnwrap(mobile.library.selectedWorkspace)
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.connect()
        try await wait { terminal.state == .connected }
        desktop.library.moveHost(hosts[0].id, to: hosts[2].id)
        try await wait { firstCloud.snapshot.profiles.first?.position != nil }
        try await secondService.merge(firstService.records())
        try await wait { mobile.library.hosts.map(\.id) == desktop.library.hosts.map(\.id) }
        XCTAssertTrue(mobile.library.selectedWorkspace === workspace)
        XCTAssertTrue(workspace.terminal === terminal)
        XCTAssertEqual(terminal.state, .connected)
        let source = try XCTUnwrap(desktop.library.selectedWorkspace)
        source.addTerminal()
        source.addTerminal()
        let originalTabs = source.tabs
        source.moveTerminal(source.tabs[2].id, to: source.tabs[0].id)
        let expected = source.tabs
        XCTAssertEqual(expected, [originalTabs[2], originalTabs[0], originalTabs[1]])
        try await wait { firstCloud.snapshot.profiles.first { $0.id == hosts[0].id }?.terminalTabs?.tabs == expected }
        try await secondService.merge(firstService.records())
        try await wait { workspace.tabs == expected }
        XCTAssertTrue(workspace.terminal === terminal)
        XCTAssertEqual(terminal.state, .connected)
        desktop.library.closeAll()
        mobile.library.closeAll()
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
        let expected = tabs.map { $0.fillingMissingResumeStrategy(with: remote.terminalResumeStrategy) }
        XCTAssertEqual(workspace.tabs, expected)
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
final class CloudHostEditingTests: XCTestCase {
    func testSaveAfterRemoteDeletionKeepsEditorAndCredentialsCanBeSavedAsCopy() async throws {
        let original = SavedHost(profile: HostProfile(hostname: "deleted.invalid", username: "test"),
                                 credentialsConfigured: false)
        let (stream, updates) = AsyncStream<HostSyncSnapshot>.makeStream()
        defer { updates.finish() }
        let service = TabSyncService(updates: updates)
        let cloud = CloudSyncModel(service: service, updates: stream)
        let device = TabSyncDevice(hosts: [original], cloud: cloud)
        try await wait { cloud.snapshot.initialized }
        device.library.editor = original
        try await service.delete(original.id)
        try await wait { cloud.pendingChanges }
        var edited = original
        edited.credentials.password = "new-local-password"
        edited.credentialsConfigured = true
        XCTAssertThrowsError(try device.library.save(edited)) { XCTAssertTrue($0 is HostSaveConflict) }
        XCTAssertNotNil(device.library.editor)
        XCTAssertEqual(device.library.hosts, [original])
        device.library.editor = nil
        XCTAssertEqual(device.library.hosts, [original])
        var copy = edited
        copy.profile = try edited.profile.recoveredCopy()
        try device.library.save(copy)
        try await wait {
            cloud.pendingDeletedProfiles.count == 1 && cloud.snapshot.baseline.contains { $0.id == copy.id }
        }
        XCTAssertEqual(device.library.hosts.count, 2)
        XCTAssertEqual(device.library.hosts.first { $0.id == copy.id }?.credentials.password, "new-local-password")
        cloud.applyChanges()
        XCTAssertEqual(device.library.hosts.map(\.id), [copy.id])
        XCTAssertTrue(device.library.hosts[0].credentialsConfigured)
        XCTAssertEqual(device.library.hosts[0].credentials.password, "new-local-password")
        device.library.closeAll()
    }

    func testRemoteDeletionArrivingAfterPasswordSaveStillRequiresExplicitApply() async throws {
        let original = SavedHost(profile: HostProfile(hostname: "deleted.invalid", username: "test"))
        let (stream, updates) = AsyncStream<HostSyncSnapshot>.makeStream()
        defer { updates.finish() }
        let service = TabSyncService(updates: updates)
        let cloud = CloudSyncModel(service: service, updates: stream)
        let device = TabSyncDevice(hosts: [original], cloud: cloud)
        try await wait { cloud.snapshot.initialized }
        var edited = original
        edited.credentials.password = "new-local-password"
        try device.library.save(edited)
        try await wait { cloud.snapshot.profiles.first?.position != nil }
        try await service.delete(original.id)
        try await wait { !cloud.pendingDeletedProfiles.isEmpty }
        XCTAssertEqual(device.library.hosts.first?.credentials.password, "new-local-password")
        XCTAssertEqual(device.hosts.hosts, device.library.hosts)
        cloud.applyChanges()
        XCTAssertTrue(device.library.hosts.isEmpty)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Cloud update was not delivered")
    }
}
