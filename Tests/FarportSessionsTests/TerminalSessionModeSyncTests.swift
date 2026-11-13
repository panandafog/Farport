import FarportCloud
import FarportCore
import FarportSessions
import XCTest

@MainActor
final class TerminalSessionModeSyncTests: XCTestCase {
    func testLocalModeChangeDisconnectsOnlyTheAffectedTerminalAndKeepsItsHistory() async throws {
        let host = SavedHost(profile: HostProfile(terminalResumeStrategy: .tmux))
        let device = TabSyncDevice(hosts: [host])
        defer { device.library.closeAll() }
        let workspace = try XCTUnwrap(device.library.selectedWorkspace)
        let first = try XCTUnwrap(workspace.terminal)
        first.connect()
        let secondID = workspace.addTerminal()
        let second = try XCTUnwrap(workspace.terminal)
        second.connect()
        try await wait { first.state == .connected && second.state == .connected }
        first.screen.write(Data("original history".utf8))
        XCTAssertTrue(workspace.requiresDisconnect(for: first.sessionID, resumeStrategy: .none))
        XCTAssertFalse(workspace.requiresDisconnect(for: secondID, resumeStrategy: .tmux))
        workspace.setResumeStrategy(.tmux, for: secondID)
        XCTAssertEqual(second.state, .connected)
        workspace.setResumeStrategy(.none, for: first.sessionID)
        XCTAssertEqual(first.state, .disconnected)
        XCTAssertFalse(first.usesTmux)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(workspace.selectedTerminalID, secondID)
        let history = try XCTUnwrap(String(data: first.screen.data, encoding: .utf8))
        XCTAssertTrue(history.contains("original history"))
        let restored = TabSyncDevice(hosts: device.hosts.hosts, saved: device.workspaces.snapshot)
        restored.library.selection = host.id
        let restoredWorkspace = try XCTUnwrap(restored.library.selectedWorkspace)
        restoredWorkspace.selectedTerminalID = first.sessionID
        XCTAssertFalse(try XCTUnwrap(restoredWorkspace.terminal).usesTmux)
        XCTAssertEqual(restoredWorkspace.terminal?.state, .disconnected)
    }

    func testCloudModeChangeWaitsForApplyAndKeepsOtherActiveTerminalsAndCredentials() async throws {
        let host = SavedHost(profile: HostProfile(hostname: "mode-sync.invalid", username: "test",
                                                 terminalResumeStrategy: .tmux),
                             credentials: HostCredentials(password: "local-only"))
        let (firstStream, firstUpdates) = AsyncStream<HostSyncSnapshot>.makeStream()
        let (secondStream, secondUpdates) = AsyncStream<HostSyncSnapshot>.makeStream()
        defer { firstUpdates.finish(); secondUpdates.finish() }
        let firstService = TabSyncService(updates: firstUpdates)
        let secondService = TabSyncService(updates: secondUpdates)
        let firstCloud = CloudSyncModel(service: firstService, updates: firstStream)
        let secondCloud = CloudSyncModel(service: secondService, updates: secondStream)
        let desktop = TabSyncDevice(hosts: [host], cloud: firstCloud)
        let mobile = TabSyncDevice(hosts: [host], cloud: secondCloud)
        defer { desktop.library.closeAll(); mobile.library.closeAll() }
        try await wait { firstCloud.snapshot.initialized && secondCloud.snapshot.initialized }
        let source = try XCTUnwrap(desktop.library.selectedWorkspace)
        let extraID = source.addTerminal()
        try await wait { firstCloud.snapshot.profiles.first?.terminalTabs?.tabs.count == 2 }
        try await secondService.merge(firstService.records())
        let destination = try XCTUnwrap(mobile.library.selectedWorkspace)
        try await wait { destination.tabs.count == 2 }
        let first = try XCTUnwrap(destination.terminal)
        first.connect()
        destination.selectedTerminalID = extraID
        let extra = try XCTUnwrap(destination.terminal)
        extra.connect()
        try await wait { first.state == .connected && extra.state == .connected }
        source.setResumeStrategy(.none, for: host.id)
        try await wait {
            firstCloud.snapshot.profiles.first?.terminalTabs?.tabs.first?.resumeStrategy == .some(.none)
        }
        try await secondService.merge(firstService.records())
        try await wait { secondCloud.pendingChanges }
        XCTAssertEqual(first.state, .connected)
        XCTAssertTrue(first.usesTmux)
        secondCloud.applyChanges()
        XCTAssertEqual(first.state, .disconnected)
        XCTAssertFalse(first.usesTmux)
        XCTAssertEqual(extra.state, .connected)
        XCTAssertTrue(destination.terminal === extra)
        XCTAssertEqual(mobile.library.hosts.first?.credentials.password, "local-only")
        XCTAssertEqual(mobile.library.hosts.first?.profile.terminalResumeStrategy, .tmux)
    }

    func testSavingHostDefaultKeepsTheExistingConnectionAndOnlyAffectsNewTabs() async throws {
        let host = SavedHost(profile: HostProfile(hostname: "default.invalid", username: "test",
                                                 terminalResumeStrategy: .tmux))
        let device = TabSyncDevice(hosts: [host])
        defer { device.library.closeAll() }
        let workspace = try XCTUnwrap(device.library.selectedWorkspace)
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.connect()
        try await wait { terminal.state == .connected }
        var updated = host
        updated.profile.terminalResumeStrategy = .none
        try device.library.save(updated)
        XCTAssertEqual(terminal.state, .connected)
        XCTAssertTrue(terminal.usesTmux)
        XCTAssertEqual(workspace.tabs.first?.resumeStrategy, .tmux)
        XCTAssertEqual(device.hosts.hosts.first?.profile.terminalTabs?.tabs.first?.resumeStrategy, .tmux)
        workspace.addTerminal()
        XCTAssertFalse(try XCTUnwrap(workspace.terminal).usesTmux)
        XCTAssertEqual(terminal.state, .connected)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Terminal/sync state did not settle")
    }
}
