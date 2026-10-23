@testable import Harbor
import HarborCore
import XCTest

@MainActor
final class WorkspaceTests: XCTestCase {
    func testTabsAndSelectedHostRestoreDisconnectedWithoutNetworkRequests() async throws {
        let storage = try WorkspaceTestStorage()
        defer { storage.remove() }
        let provider = WorkspaceTestProvider()
        let model = storage.library(provider)
        let first = try XCTUnwrap(model.selectedWorkspace)
        let originalID = try XCTUnwrap(first.selectedTerminalID)
        let secondID = first.addTerminal()
        first.renameTerminal(secondID, title: "  Logs  ")
        first.mode = .files
        model.selection = storage.hosts[1].id
        model.selectedWorkspace?.addTerminal()
        model.closeAll()

        let restored = storage.library(provider)
        defer { restored.closeAll() }
        XCTAssertEqual(restored.selection, storage.hosts[1].id)
        XCTAssertEqual(restored.selectedWorkspace?.tabs.count, 2)
        restored.selection = storage.hosts[0].id
        let workspace = try XCTUnwrap(restored.selectedWorkspace)
        XCTAssertEqual(workspace.tabs.map(\.id), [originalID, secondID])
        XCTAssertEqual(workspace.tabs.map(\.title), ["Terminal 1", "Logs"])
        XCTAssertEqual(workspace.selectedTerminalID, secondID)
        XCTAssertEqual(workspace.mode, .files)
        XCTAssertEqual(workspace.terminal?.state, .disconnected)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testSwitchingRetainsHistoryAndClosingOnlyDisconnectsItsOwnTab() async throws {
        let host = SavedHost(profile: HostProfile(terminalResumeStrategy: .tmux))
        let provider = WorkspaceTestProvider()
        let workspace = WorkspaceModel(host: host, provider: provider)
        defer { workspace.close() }
        let first = try XCTUnwrap(workspace.terminal)
        first.connect()
        try await waitUntil { first.state == .connected }
        first.view.feed(text: "history-from-first")
        let secondID = workspace.addTerminal()
        let second = try XCTUnwrap(workspace.terminal)
        second.connect()
        try await waitUntil { second.state == .connected }
        XCTAssertNotEqual(first.sessionLabel, second.sessionLabel)
        workspace.selectedTerminalID = host.id
        XCTAssertTrue(workspace.terminal === first)
        let history = String(data: first.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(history.contains("history-from-first"))
        workspace.closeTerminal(secondID)
        XCTAssertEqual(second.state, .disconnected)
        XCTAssertEqual(first.state, .connected)
        let requests = await provider.requests
        XCTAssertEqual(requests, [host.id, secondID])
        workspace.closeTerminal(host.id)
        XCTAssertNil(workspace.terminal)
        XCTAssertTrue(workspace.tabs.isEmpty)
        let newID = workspace.addTerminal()
        XCTAssertNotEqual(newID, host.id)
        XCTAssertEqual(workspace.terminal?.state, .disconnected)
    }

    func testEditingHostKeepsTabIdentitiesAndDeletionPrunesOnlyThatHost() throws {
        let storage = try WorkspaceTestStorage()
        defer { storage.remove() }
        let model = storage.library(WorkspaceTestProvider())
        defer { model.closeAll() }
        let workspace = try XCTUnwrap(model.selectedWorkspace)
        let secondID = workspace.addTerminal()
        var host = storage.hosts[0]
        host.profile.name = "Renamed host"
        try model.save(host)
        XCTAssertEqual(model.selectedWorkspace?.tabs, workspace.tabs)
        XCTAssertEqual(model.selectedWorkspace?.selectedTerminalID, secondID)
        XCTAssertEqual(model.selectedWorkspace?.host.profile.name, "Renamed host")
        model.delete(host)
        XCTAssertEqual(model.selection, storage.hosts[1].id)
        let saved = try storage.workspaces.load()
        XCTAssertEqual(saved.hosts.map(\.hostID), [storage.hosts[1].id])
    }

    func testStaleHostsAreIgnoredAndRemovedOnNextSave() throws {
        let storage = try WorkspaceTestStorage()
        defer { storage.remove() }
        let stale = HostWorkspace(hostID: UUID())
        try storage.workspaces.save(WorkspaceSnapshot(selectedHostID: stale.hostID, hosts: [stale]))
        let model = storage.library(WorkspaceTestProvider())
        XCTAssertEqual(model.selection, storage.hosts[0].id)
        model.closeAll()
        XCTAssertEqual(try storage.workspaces.load().hosts.map(\.hostID), storage.hosts.map(\.id))
    }

    func testCorruptWorkspaceIsNeverOverwrittenByChangesOrTermination() throws {
        let storage = try WorkspaceTestStorage()
        defer { storage.remove() }
        let bytes = Data("broken workspace".utf8)
        try bytes.write(to: storage.workspaces.url)
        let model = storage.library(WorkspaceTestProvider())
        XCTAssertNotNil(model.error)
        model.selectedWorkspace?.addTerminal()
        model.selection = storage.hosts[1].id
        model.closeAll()
        XCTAssertEqual(try Data(contentsOf: storage.workspaces.url), bytes)
    }

    func testCloseChoosesNeighborAndRenameNeverChangesSessionID() throws {
        let workspace = WorkspaceModel(host: SavedHost(), provider: WorkspaceTestProvider())
        let first = try XCTUnwrap(workspace.selectedTerminalID)
        let second = workspace.addTerminal()
        let third = workspace.addTerminal()
        workspace.selectedTerminalID = second
        workspace.renameTerminal(second, title: "Build")
        XCTAssertEqual(workspace.terminal?.sessionID, second)
        workspace.renameTerminal(second, title: "  ")
        XCTAssertEqual(workspace.tabs[1].title, "Build")
        workspace.closeTerminal(second)
        XCTAssertEqual(workspace.selectedTerminalID, third)
        workspace.selectNextTerminal(offset: 1)
        XCTAssertEqual(workspace.selectedTerminalID, first)
        workspace.selectNextTerminal(offset: -1)
        XCTAssertEqual(workspace.selectedTerminalID, third)
        workspace.close()
    }

    func testReconfigurationDisconnectsEveryTabRetainsOutputAndUsesNewProvider() async throws {
        let oldProvider = WorkspaceTestProvider()
        let newProvider = WorkspaceTestProvider()
        let host = SavedHost(profile: HostProfile(hostname: "old.test", username: "test"))
        let workspace = WorkspaceModel(host: host, provider: oldProvider)
        defer { workspace.close() }
        let first = try XCTUnwrap(workspace.terminal)
        first.connect()
        try await waitUntil { first.state == .connected }
        first.view.feed(text: "retained-across-route-change")
        workspace.addTerminal()
        let second = try XCTUnwrap(workspace.terminal)
        second.connect()
        try await waitUntil { second.state == .connected }
        var updated = host
        updated.profile.hostname = "new.test"
        workspace.reconfigure(host: updated, provider: newProvider, routeSummary: "via New gateway")
        XCTAssertEqual(first.state, .disconnected)
        XCTAssertEqual(second.state, .disconnected)
        XCTAssertTrue(workspace.terminal === second)
        XCTAssertEqual(second.endReason, "Connection settings changed")
        XCTAssertEqual(workspace.host.profile.hostname, "new.test")
        let history = String(data: first.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(history.contains("retained-across-route-change"))
        second.connect()
        try await waitUntil { second.state == .connected }
        let oldRequests = await oldProvider.requests
        let newRequests = await newProvider.requests
        XCTAssertEqual(oldRequests.count, 2)
        XCTAssertEqual(newRequests, [second.sessionID])
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private struct WorkspaceTestStorage {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let hosts = [SavedHost(profile: HostProfile(hostname: "one.test", username: "test")),
                 SavedHost(profile: HostProfile(hostname: "two.test", username: "test"))]
    var repository: JSONHostRepository { JSONHostRepository(url: root.appendingPathComponent("hosts.json")) }
    var workspaces: JSONWorkspaceRepository { JSONWorkspaceRepository(url: root.appendingPathComponent("tabs.json")) }

    init() throws { try repository.save(hosts) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func library(_ provider: any ConnectionProvider) -> LibraryModel {
        LibraryModel(repository: repository, workspaceRepository: workspaces, provider: provider)
    }
}

private actor WorkspaceTestProvider: ConnectionProvider {
    private(set) var requests: [UUID] = []

    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        requests.append(sessionID)
        return WorkspaceTestTerminal()
    }

    func files(for host: SavedHost) async throws -> any RemoteFileSession {
        throw HarborError.message("Unused file capability")
    }
}

private actor WorkspaceTestTerminal: TerminalSession {
    private let output = AsyncStream<Data>.makeStream()

    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        for await data in output.stream { await onOutput(data) }
    }

    func send(_ data: Data) async throws {}
    func resize(_ size: TerminalSize) async throws {}
    func checkConnection(timeout: TimeInterval) async throws {}
    func close() async { output.continuation.finish() }
}
