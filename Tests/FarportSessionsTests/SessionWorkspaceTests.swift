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
