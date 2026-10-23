@testable import Harbor
import HarborCloud
import HarborCore
import XCTest

@MainActor
final class CloudSyncModelTests: XCTestCase {
    func testIncomingProfileIsImportedWithoutCredentialsAndMetadataKeepsLocalSecrets() async throws {
        let fixture = try CloudLibraryFixture()
        defer { fixture.remove() }
        var existing = fixture.original.profile
        existing.notes = "Edited on another device"
        let remote = HostProfile(hostname: "remote.test", username: "remote")
        fixture.send([existing, remote], baseline: [fixture.original.profile])
        try await wait { fixture.library.hosts.count == 2 }
        XCTAssertEqual(fixture.library.hosts.first?.credentials, fixture.original.credentials)
        XCTAssertTrue(fixture.library.hosts.first?.credentialsConfigured == true)
        let imported = try XCTUnwrap(fixture.library.hosts.first { $0.id == remote.id })
        XCTAssertFalse(imported.credentialsConfigured)
        XCTAssertThrowsError(try imported.validate())
        XCTAssertEqual(try fixture.repository.load(), fixture.library.hosts)
        let bytes = try String(contentsOf: fixture.repository.url, encoding: .utf8)
        XCTAssertFalse(bytes.contains("device-only-password"))
    }

    func testEditorDefersRemoteUpdateAndApplyingPreservesTerminalHistory() async throws {
        let fixture = try CloudLibraryFixture()
        defer { fixture.remove() }
        let workspace = try XCTUnwrap(fixture.library.selectedWorkspace)
        let terminal = try XCTUnwrap(workspace.terminal)
        terminal.view.feed(text: "history-before-cloud-update")
        fixture.library.editor = fixture.original
        var remote = fixture.original.profile
        remote.hostname = "changed.test"
        fixture.send([remote], baseline: [fixture.original.profile])
        try await wait { fixture.cloud.pendingChanges }
        XCTAssertEqual(fixture.library.hosts, [fixture.original])
        fixture.cloud.applyChanges()
        XCTAssertEqual(fixture.library.hosts, [fixture.original])
        fixture.library.editor = nil
        try await wait { fixture.library.hosts.first?.profile == remote }
        XCTAssertTrue(fixture.library.selectedWorkspace === workspace)
        XCTAssertTrue(workspace.terminal === terminal)
        let history = String(data: terminal.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(history.contains("history-before-cloud-update"))
        XCTAssertFalse(try XCTUnwrap(fixture.library.hosts.first).credentialsConfigured)
        XCTAssertEqual(terminal.state, .disconnected)
    }

    func testStaleCloudSnapshotCannotDeleteANewlySavedLocalHost() async throws {
        let fixture = try CloudLibraryFixture()
        defer { fixture.remove() }
        let newHost = SavedHost(profile: HostProfile(hostname: "new.test", username: "local"))
        fixture.library.editor = newHost
        try fixture.library.save(newHost)
        // An already-queued cloud event still has the baseline from before this local save.
        fixture.send([fixture.original.profile], baseline: [fixture.original.profile])
        try await wait { fixture.cloud.snapshot.initialized }
        XCTAssertEqual(Set(fixture.library.hosts.map(\.id)), [fixture.original.id, newHost.id])
        XCTAssertEqual(try fixture.repository.load(), fixture.library.hosts)
        XCTAssertFalse(fixture.cloud.pendingChanges)
        fixture.cloud.applyChanges()
        XCTAssertEqual(fixture.library.hosts.count, 2)
        XCTAssertNotNil(fixture.cloud.error)
    }

    func testRemoteGatewayDeletionDoesNotConvertDependentHostToDirectConnection() throws {
        let fixture = try CloudLibraryFixture()
        defer { fixture.remove() }
        let target = SavedHost(profile: HostProfile(hostname: "internal.test", username: "user",
                                                  jumpHostIDs: [fixture.original.id]))
        try fixture.library.save(target)
        try fixture.library.applySyncedProfiles([target.profile])
        XCTAssertEqual(fixture.library.hosts.first?.profile.jumpHostIDs, [fixture.original.id])
        XCTAssertThrowsError(try ConnectionRoute(to: target, library: fixture.library.hosts))
        XCTAssertEqual(fixture.library.selectedWorkspace?.routeSummary, "ProxyJump route unavailable")
    }

    func testActiveTerminalDefersUntilExplicitApplyAndRetainsItsBuffer() async throws {
        let fixture = try CloudLibraryFixture(provider: CloudTerminalProvider())
        defer { fixture.remove() }
        let terminal = try XCTUnwrap(fixture.library.selectedWorkspace?.terminal)
        terminal.connect()
        try await wait { terminal.state == .connected }
        terminal.view.feed(text: "active-output-before-sync")
        var remote = fixture.original.profile
        remote.name = "Remote rename"
        fixture.send([remote], baseline: [fixture.original.profile])
        try await wait { fixture.cloud.pendingChanges }
        XCTAssertEqual(terminal.state, .connected)
        XCTAssertEqual(fixture.library.hosts, [fixture.original])
        fixture.cloud.applyChanges()
        XCTAssertEqual(terminal.state, .disconnected)
        XCTAssertTrue(fixture.library.selectedWorkspace?.terminal === terminal)
        let history = String(data: terminal.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(history.contains("active-output-before-sync"))
        XCTAssertEqual(fixture.library.hosts.first?.profile, remote)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Cloud update was not delivered")
    }
}

private actor StubHostSyncService: HostSyncService {
    func resume(profiles: [HostProfile]) {}
    func enable(profiles: [HostProfile]) {}
    func disable() {}
    func refresh(profiles: [HostProfile]) {}
    func localChanged(profiles: [HostProfile]) {}
    func applied(profiles: [HostProfile]) {}
    func dismissConflict(_ id: String) {}
}

@MainActor
private struct CloudLibraryFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let original = SavedHost(profile: HostProfile(hostname: "original.test", username: "local"),
                             credentials: HostCredentials(password: "device-only-password"))
    let repository: ProtectedHostRepository
    let cloud: CloudSyncModel
    let library: LibraryModel
    let continuation: AsyncStream<HostSyncSnapshot>.Continuation

    init(provider: (any ConnectionProvider)? = nil) throws {
        repository = ProtectedHostRepository(url: root.appendingPathComponent("hosts.json"), secrets: TestSecretStore())
        try repository.save([original])
        let (stream, continuation) = AsyncStream<HostSyncSnapshot>.makeStream()
        self.continuation = continuation
        cloud = CloudSyncModel(service: StubHostSyncService(), updates: stream)
        library = LibraryModel(repository: repository, workspaceRepository: JSONWorkspaceRepository(
            url: root.appendingPathComponent("workspace.json")), provider: provider, cloud: cloud)
    }

    func send(_ profiles: [HostProfile], baseline: [HostProfile]) {
        continuation.yield(HostSyncSnapshot(enabled: true, initialized: true, profiles: profiles, baseline: baseline))
    }

    func remove() {
        continuation.finish()
        library.closeAll()
        try? FileManager.default.removeItem(at: root)
    }
}

private struct CloudTerminalProvider: ConnectionProvider {
    func terminal(for host: SavedHost, sessionID: UUID) -> any TerminalSession { CloudTerminal() }
    func files(for host: SavedHost) throws -> any RemoteFileSession { throw HarborError.message("Unused") }
}

private actor CloudTerminal: TerminalSession {
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
