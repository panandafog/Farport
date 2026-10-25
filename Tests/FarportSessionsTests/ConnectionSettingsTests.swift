import FarportCore
import FarportSessions
import XCTest

@MainActor
final class ConnectionSettingsTests: XCTestCase {
    func testMissingCredentialsOffersTargetSettingsAndClearsAfterEditing() async throws {
        let host = SavedHost(credentialsConfigured: false)
        let failure = TerminalConnectionError.configuration("Set credentials before connecting")
        let provider = SettingsFailureProvider(failure: failure)
        let model = RecordingTerminal(host: host, provider: provider)
        model.screen.write(Data("retained history".utf8))
        model.connect()
        try await wait { model.error != nil }
        XCTAssertEqual(model.settingsHostID, host.id)
        XCTAssertEqual(model.error, failure.localizedDescription)
        model.reconfigure(host: SavedHost(profile: host.profile), provider: provider)
        XCTAssertNil(model.error)
        XCTAssertNil(model.settingsHostID)
        XCTAssertEqual(String(data: model.screen.data, encoding: .utf8)?.hasPrefix("retained history"), true)
    }

    func testGatewayAuthenticationOffersGatewaySettingsInTerminalAndFiles() async throws {
        let target = SavedHost()
        let gatewayID = UUID()
        let failure = TerminalConnectionError.route(stage: "Jump host", cause: .endpoint(
            hostID: gatewayID, cause: .authentication
        ))
        let provider = SettingsFailureProvider(failure: failure)
        let terminal = RecordingTerminal(host: target, provider: provider)
        let files = FilesModel(host: target, provider: provider)
        terminal.connect()
        files.connect()
        try await wait { terminal.error != nil && !files.busy }
        XCTAssertEqual(terminal.settingsHostID, gatewayID)
        XCTAssertEqual(files.settingsHostID, gatewayID)
        XCTAssertFalse(failure.allowsReconnect)
        XCTAssertEqual(terminal.error, failure.localizedDescription)
        files.reconfigure(host: target, provider: provider)
        XCTAssertNil(files.error)
        XCTAssertNil(files.settingsHostID)
    }

    func testSettingsActionDoesNotReplacePermissionOrServerTrustActions() {
        let hostID = UUID()
        let key = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data([1, 2, 3]))
        let challenge = HostKeyChallenge(endpoint: ServerEndpoint(hostname: "test.invalid", port: 22), presented: key)
        for cause in [TerminalConnectionError.localNetworkPermission, .serverTrust(challenge), .transport("offline")] {
            let failure = TerminalConnectionError.endpoint(hostID: hostID, cause: cause)
            XCTAssertNil(failure.settingsHostID(fallback: UUID()))
            XCTAssertEqual(failure.requiresLocalNetworkPermission, cause.requiresLocalNetworkPermission)
            XCTAssertEqual(failure.hostKeyChallenge?.endpoint, cause.hostKeyChallenge?.endpoint)
            XCTAssertEqual(failure.allowsReconnect, cause.allowsReconnect)
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}

private struct SettingsFailureProvider: ConnectionProvider {
    let failure: TerminalConnectionError
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession { throw failure }
    func files(for host: SavedHost) async throws -> any RemoteFileSession { throw failure }
}
