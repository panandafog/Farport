#if DEBUG
import FarportCore
import FarportDemo
import XCTest

final class PublicHostTests: XCTestCase {
    func testPublicHostsUseInjectedTransportWithoutConnectingFictionalOrEditedHosts() async throws {
        let live = LiveProbe()
        let provider = DemoConnectionProvider(publicProvider: live)
        let bandit = DemoCatalog.publicHosts[0]
        do {
            _ = try await provider.terminal(for: bandit, sessionID: bandit.id)
            XCTFail("Expected the injected provider")
        } catch ProbeError.reachedTransport {} catch { XCTFail("Unexpected error: \(error)") }
        let wing = DemoCatalog.publicHosts[2]
        do {
            _ = try await provider.files(for: wing)
            XCTFail("Expected the injected provider")
        } catch ProbeError.reachedTransport {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            _ = try await provider.terminal(for: wing)
            XCTFail("SFTP-only host must reject terminal connections")
        } catch is HarborError {} catch { XCTFail("Unexpected error: \(error)") }

        var fictional = DemoCatalog.offlineHosts[0]
        fictional.profile.hostname = bandit.profile.hostname
        let session = try await provider.terminal(for: fictional)
        await session.close()
        let attempts = await live.attempts
        XCTAssertEqual(attempts, [bandit.id, wing.id])
    }

    func testEditingPublicEndpointCredentialsRouteOrModeNeverSendsPublishedPasswordElsewhere() async {
        let live = LiveProbe()
        let provider = DemoConnectionProvider(publicProvider: live)
        let original = DemoCatalog.publicHosts[0]
        var endpoint = original, credentials = original, route = original, mode = original
        endpoint.profile.hostname = "localhost"
        credentials.credentials.password = "changed"
        route.profile.jumpHostIDs = [UUID()]
        mode.profile.terminalResumeStrategy = .tmux
        for host in [endpoint, credentials, route, mode] {
            do {
                _ = try await provider.files(for: host)
                XCTFail("Edited public settings must be rejected")
            } catch is HarborError {} catch { XCTFail("Unexpected error: \(error)") }
        }
        let attempts = await live.attempts
        XCTAssertTrue(attempts.isEmpty)
    }

    func testPublicHostsCannotFallBackToSimulatedSuccessWithoutLiveTransport() async {
        do {
            _ = try await DemoConnectionProvider().terminal(for: DemoCatalog.publicHosts[0])
            XCTFail("A public host must never look connected through the simulation")
        } catch is HarborError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testDemoTrustRequiresExplicitApprovalAndDoesNotSurviveNewStore() throws {
        let repository = KnownHostRepository(secrets: DemoSecretStore())
        let endpoint = ServerEndpoint(DemoCatalog.publicHosts[0].profile)
        let key = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("public-test-key".utf8))
        let challenge = HostKeyChallenge(endpoint: endpoint, presented: key)
        XCTAssertThrowsError(try repository.verify(endpoint, key: key))
        try repository.trust(challenge)
        XCTAssertNoThrow(try repository.verify(endpoint, key: key))
        XCTAssertThrowsError(try repository.verify(endpoint,
            key: ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("changed-key".utf8))))
        XCTAssertThrowsError(try KnownHostRepository(secrets: DemoSecretStore()).verify(endpoint, key: key))
    }
}

private enum ProbeError: Error { case reachedTransport }

private actor LiveProbe: ConnectionProvider {
    var attempts: [UUID] = []
    func terminal(for host: SavedHost, sessionID: UUID) throws -> any TerminalSession {
        attempts.append(host.id)
        throw ProbeError.reachedTransport
    }
    func files(for host: SavedHost) throws -> any RemoteFileSession {
        attempts.append(host.id)
        throw ProbeError.reachedTransport
    }
}
#endif
