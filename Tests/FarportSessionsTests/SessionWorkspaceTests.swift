import FarportCore
import FarportSessions
import XCTest

@MainActor
final class SessionWorkspaceTests: XCTestCase {
    func testLargeAndNegativeTabOffsetsWrapWithoutCrashing() {
        let workspace = makeWorkspace()
        workspace.addTerminal()
        workspace.addTerminal()
        workspace.selectedTerminalID = workspace.tabs[0].id
        workspace.selectNextTerminal(offset: -10)
        XCTAssertEqual(workspace.selectedTerminalID, workspace.tabs[2].id)
        workspace.selectNextTerminal(offset: 10)
        XCTAssertEqual(workspace.selectedTerminalID, workspace.tabs[0].id)
        workspace.selectNextTerminal(offset: Int.min)
        XCTAssertTrue(workspace.tabs.contains { $0.id == workspace.selectedTerminalID })
    }

    func testRenamingKeepsIdentityAndRendererWhileRestoreDoesNotConnect() throws {
        let workspace = makeWorkspace()
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.screen.write(Data("retained screen".utf8))
        workspace.renameTerminal(terminal.sessionID, title: "  Work  ")
        XCTAssertTrue(workspace.terminal === terminal)
        XCTAssertEqual(workspace.tabs[0].title, "Work")
        XCTAssertEqual(workspace.tabs[0].id, terminal.sessionID)
        let restored = makeWorkspace(host: workspace.host, snapshot: workspace.snapshot)
        XCTAssertEqual(restored.terminal?.state, .disconnected)
        XCTAssertEqual(restored.terminal?.sessionID, terminal.sessionID)
        XCTAssertEqual(restored.tabs, workspace.tabs)
    }

    func testMovingTabsPreservesSelectionRendererAndReportsOneChange() throws {
        let workspace = makeWorkspace()
        workspace.addTerminal()
        workspace.addTerminal()
        let tabs = workspace.tabs
        let terminal = try XCTUnwrap(workspace.terminal)
        let selection = workspace.selectedTerminalID
        var changes = 0
        workspace.changed = { changes += 1 }
        workspace.moveTerminal(tabs[2].id, to: tabs[0].id)
        XCTAssertEqual(workspace.tabs.map(\.id), [tabs[2].id, tabs[0].id, tabs[1].id])
        XCTAssertEqual(workspace.selectedTerminalID, selection)
        XCTAssertTrue(workspace.terminal === terminal)
        XCTAssertEqual(changes, 1)
    }

    func testPerTabModesKeepSeparateTerminalsAndSurviveWorkspaceRestoration() throws {
        let host = SavedHost(profile: HostProfile(terminalResumeStrategy: .tmux))
        let workspace = makeWorkspace(host: host)
        let first = try XCTUnwrap(workspace.terminal)
        first.screen.write(Data("retained history".utf8))
        XCTAssertTrue(first.usesTmux)
        let secondID = workspace.addTerminal()
        let second = try XCTUnwrap(workspace.terminal)
        workspace.setResumeStrategy(.none, for: first.sessionID)
        XCTAssertFalse(first.usesTmux)
        XCTAssertTrue(second.usesTmux)
        workspace.selectedTerminalID = first.sessionID
        XCTAssertTrue(workspace.terminal === first)
        let history = try XCTUnwrap(String(data: first.screen.data, encoding: .utf8))
        XCTAssertTrue(history.contains("retained history"))
        let restored = makeWorkspace(host: host, snapshot: workspace.snapshot)
        XCTAssertFalse(try XCTUnwrap(restored.terminal).usesTmux)
        restored.selectedTerminalID = secondID
        XCTAssertTrue(try XCTUnwrap(restored.terminal).usesTmux)
        XCTAssertEqual(workspace.tabs.first { $0.id == secondID }?.resumeStrategy, .tmux)
    }

    func testHostDefaultOnlyInitializesNewTabsAndDoesNotChangeExistingModes() throws {
        var host = SavedHost(profile: HostProfile(terminalResumeStrategy: .tmux))
        let workspace = makeWorkspace(host: host)
        let first = try XCTUnwrap(workspace.terminal)
        workspace.setResumeStrategy(.tmux, for: first.sessionID)
        workspace.addTerminal()
        let second = try XCTUnwrap(workspace.terminal)
        host.profile.terminalResumeStrategy = .none
        workspace.reconfigure(host: host, provider: IdleProvider(), routeSummary: nil)
        XCTAssertTrue(first.usesTmux)
        XCTAssertTrue(second.usesTmux)
        workspace.addTerminal()
        XCTAssertFalse(try XCTUnwrap(workspace.terminal).usesTmux)
        workspace.setResumeStrategy(.none, for: first.sessionID)
        XCTAssertFalse(first.usesTmux)
        XCTAssertTrue(second.usesTmux)
    }

    func testIncomingLegacyTabsKeepTheCapturedModeAfterHostDefaultChanges() throws {
        var host = SavedHost(profile: HostProfile(terminalResumeStrategy: .tmux))
        let workspace = makeWorkspace(host: host)
        let terminal = try XCTUnwrap(workspace.terminal)
        let legacy = TerminalTab(id: terminal.sessionID, title: "Remote rename")
        var layout = SyncedTerminalTabs()
        try layout.record([legacy], device: UUID())
        host.profile.terminalResumeStrategy = .none
        host.profile.terminalTabs = layout
        XCTAssertTrue(workspace.canApplyTerminalTabs(layout))
        workspace.applyTerminalTabs(host: host)
        XCTAssertTrue(workspace.terminal === terminal)
        XCTAssertTrue(terminal.usesTmux)
        XCTAssertEqual(workspace.tabs[0].resumeStrategy, .tmux)
        XCTAssertEqual(workspace.tabs[0].title, "Remote rename")
        workspace.addTerminal()
        XCTAssertFalse(try XCTUnwrap(workspace.terminal).usesTmux)
    }

    private func makeWorkspace(host: SavedHost = SavedHost(), snapshot: HostWorkspace? = nil)
        -> SessionWorkspace<RecordingTerminal> {
        SessionWorkspace(host: host, provider: IdleProvider(), snapshot: snapshot) {
            RecordingTerminal(host: $0, provider: $1, sessionID: $2, trust: $3)
        }
    }
}

private struct IdleProvider: ConnectionProvider {
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        XCTFail("Workspace restoration must never connect")
        throw CancellationError()
    }
    func files(for host: SavedHost) async throws -> any RemoteFileSession {
        XCTFail("Workspace restoration must never connect")
        throw CancellationError()
    }
}
