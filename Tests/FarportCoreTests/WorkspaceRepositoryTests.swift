@testable import FarportCore
import XCTest

final class WorkspaceRepositoryTests: XCTestCase {
    func testWorkspaceRoundTripPreservesOrderNamesAndSelectionsWithoutSecrets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workspace.json")
        var host = HostWorkspace(hostID: UUID())
        let second = TerminalTab(title: "Logs", resumeStrategy: .tmux)
        host.terminals.append(second)
        host.selectedTerminalID = second.id
        host.mode = .files
        let original = WorkspaceSnapshot(selectedHostID: host.hostID, hosts: [host])
        try JSONWorkspaceRepository(url: url).save(original)
        XCTAssertEqual(try JSONWorkspaceRepository(url: url).load(), original)
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains("password"))
        XCTAssertFalse(json.contains("credentials"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testDefaultTabReusesLegacyTmuxIdentity() {
        let host = HostProfile()
        let workspace = HostWorkspace(hostID: host.id)
        XCTAssertEqual(workspace.terminals.first?.tmuxSessionName, host.tmuxSessionName)
        XCTAssertEqual(workspace.selectedTerminalID, workspace.terminals.first?.id)
    }

    func testPerTabModesRoundTripAndLegacyModeCanBeFilledOnce() throws {
        let old = try JSONDecoder().decode(TerminalTab.self, from: Data(
            "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"Legacy\"}".utf8
        ))
        XCTAssertNil(old.resumeStrategy)
        let migrated = old.fillingMissingResumeStrategy(with: .tmux)
        XCTAssertEqual(migrated.effectiveResumeStrategy(default: .none), .tmux)
        let tabs = [old, TerminalTab(title: "SSH", resumeStrategy: .some(.none)),
                    TerminalTab(title: "Persistent", resumeStrategy: .tmux)]
        let restored = try JSONDecoder().decode([TerminalTab].self, from: JSONEncoder().encode(tabs))
        XCTAssertEqual(restored, tabs)
        XCTAssertEqual(restored[1].effectiveResumeStrategy(default: .tmux), .none)
        XCTAssertEqual(restored[2].effectiveResumeStrategy(default: .none), .tmux)
    }

    func testInvalidSelectionsAndDuplicateIdentitiesAreRejected() {
        var host = HostWorkspace(hostID: UUID())
        host.selectedTerminalID = UUID()
        XCTAssertThrowsError(try WorkspaceSnapshot(hosts: [host]).validate())
        host.selectedTerminalID = host.terminals.first?.id
        host.terminals.append(host.terminals[0])
        XCTAssertThrowsError(try WorkspaceSnapshot(hosts: [host]).validate())
        XCTAssertThrowsError(try WorkspaceSnapshot(hosts: [host, host]).validate())
    }

    func testClosedLastTabAndMissingFileAreSupported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(try JSONWorkspaceRepository(url: url).load().hosts.isEmpty)
        var host = HostWorkspace(hostID: UUID())
        host.terminals = []
        host.selectedTerminalID = nil
        XCTAssertNoThrow(try WorkspaceSnapshot(hosts: [host]).validate())
    }

    func testCorruptAndFutureDocumentsAreNotReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        for text in ["broken json", "{\"schemaVersion\":99,\"hosts\":[]}"] {
            let bytes = Data(text.utf8)
            try bytes.write(to: url)
            XCTAssertThrowsError(try JSONWorkspaceRepository(url: url).load())
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
}
