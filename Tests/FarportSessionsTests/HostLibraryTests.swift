import FarportCore
import FarportSessions
import XCTest

@MainActor
final class HostLibraryTests: XCTestCase {
    func testEditGatewayReconfiguresDependentsAndPreservesTerminalIdentity() throws {
        let gateway = SavedHost(profile: HostProfile(name: "Gateway", hostname: "gateway", username: "test"))
        let target = SavedHost(profile: HostProfile(hostname: "target", username: "test", jumpHostIDs: [gateway.id]))
        let repository = LibraryTestRepository([gateway, target])
        let library = makeLibrary(repository)
        library.selection = target.id
        let original = try XCTUnwrap(library.selectedWorkspace?.terminal)
        var changed = gateway
        changed.profile.hostname = "replacement"
        try library.save(changed)
        library.selection = target.id
        XCTAssertTrue(library.selectedWorkspace?.terminal === original)
        XCTAssertEqual(library.selectedWorkspace?.routeSummary, "via Gateway")
        XCTAssertEqual(repository.hosts.first?.profile.hostname, "replacement")
        library.delete(changed)
        XCTAssertEqual(library.hosts.count, 2)
        XCTAssertNotNil(library.error)
    }

    func testFailedSaveDoesNotReplaceLibraryOrWorkspace() throws {
        let host = SavedHost(profile: HostProfile(hostname: "original", username: "test"))
        let repository = LibraryTestRepository([host])
        let library = makeLibrary(repository)
        let terminal = library.selectedWorkspace?.terminal
        var changed = host
        changed.profile.hostname = "changed"
        repository.failWrites = true
        XCTAssertThrowsError(try library.save(changed))
        XCTAssertEqual(library.hosts, [host])
        XCTAssertTrue(library.selectedWorkspace?.terminal === terminal)
    }

    func testImportUsesLocalCredentialsAndRestoresWithoutConnecting() throws {
        let host = SavedHost(profile: HostProfile(hostname: "original", username: "test"),
                             credentials: HostCredentials(password: "local-only"))
        let repository = LibraryTestRepository([host])
        let library = makeLibrary(repository)
        var renamed = host.profile
        renamed.name = "Cloud name"
        try library.applySyncedProfiles([renamed])
        XCTAssertEqual(library.hosts.first?.credentials.password, "local-only")
        XCTAssertEqual(library.selectedWorkspace?.terminal?.state, .disconnected)
        renamed.hostname = "new-endpoint"
        try library.applySyncedProfiles([renamed])
        XCTAssertFalse(try XCTUnwrap(library.hosts.first).credentialsConfigured)
    }

    func testReorderPreservesWorkspacesAndSelectionAndFailedWriteKeepsOrder() throws {
        let hosts = (0..<3).map { SavedHost(profile: HostProfile(hostname: "host\($0).invalid", username: "test")) }
        let repository = LibraryTestRepository(hosts)
        let library = makeLibrary(repository)
        let workspace = try XCTUnwrap(library.selectedWorkspace)
        let terminal = try XCTUnwrap(workspace.terminal)
        library.moveHost(hosts[0].id, to: hosts[2].id)
        XCTAssertEqual(library.hosts.map(\.id), [hosts[1].id, hosts[2].id, hosts[0].id])
        XCTAssertEqual(library.selection, hosts[0].id)
        XCTAssertTrue(library.selectedWorkspace === workspace)
        XCTAssertTrue(workspace.terminal === terminal)
        let ordered = library.hosts
        repository.failWrites = true
        library.moveHost(hosts[0].id, to: hosts[1].id)
        XCTAssertEqual(library.hosts, ordered)
        XCTAssertNotNil(library.error)
    }

    func testMovingFilteredHostsKeepsHiddenHostsInPlace() {
        let hosts = ["visible-first", "hidden", "visible-last"].map {
            SavedHost(profile: HostProfile(hostname: $0, username: "test"))
        }
        let library = makeLibrary(LibraryTestRepository(hosts))
        library.query = "visible"
        library.moveHosts(from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(library.hosts.map(\.id), [hosts[2].id, hosts[1].id, hosts[0].id])
    }

    private func makeLibrary(_ repository: LibraryTestRepository) -> HostLibraryModel<TerminalSessionModel> {
        HostLibraryModel(repository: repository, workspaceRepository: LibraryTestWorkspace(),
                         makeProvider: { _ in LibraryTestProvider() }, makeTerminal: {
            TerminalSessionModel(host: $0, provider: $1, sessionID: $2, trust: $3, output: LibraryTestOutput())
        })
    }
}

private final class LibraryTestRepository: HostRepository {
    var hosts: [SavedHost]
    var failWrites = false
    init(_ hosts: [SavedHost]) { self.hosts = hosts }
    func load() -> [SavedHost] { hosts }
    func save(_ hosts: [SavedHost]) throws {
        if failWrites { throw HarborError.message("Test write failure") }
        self.hosts = hosts
    }
}

private struct LibraryTestWorkspace: WorkspaceRepository {
    func load() -> WorkspaceSnapshot { WorkspaceSnapshot() }
    func save(_ snapshot: WorkspaceSnapshot) throws { try snapshot.validate() }
}

private struct LibraryTestProvider: ConnectionProvider {
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        throw CancellationError()
    }
    func files(for host: SavedHost) async throws -> any RemoteFileSession { throw CancellationError() }
}

@MainActor
private final class LibraryTestOutput: TerminalOutput {
    func write(_ data: Data) {}
    func setCursorVisible(_ visible: Bool) {}
    func focus() {}
}
