import Foundation
import HarborCore
import HarborSSH
import XCTest

final class ServerKeyIntegrationTests: XCTestCase {
    func testDefaultProviderRejectsUnknownServerAndReportsActualFingerprint() async throws {
        let fixture = try JumpTestFixture()
        var direct = fixture.target
        direct.profile.hostname = "127.0.0.1"
        direct.profile.jumpHostIDs = []
        let actual = try FixtureTrust.key(fixture.keyDirectory.appendingPathComponent("server-host.pub"))
        do {
            let session = try await SSHConnectionProvider().files(for: direct)
            await session.close()
            XCTFail("An unknown key must not be accepted")
        } catch let failure as TerminalConnectionError {
            let challenge = try XCTUnwrap(failure.hostKeyChallenge)
            XCTAssertEqual(challenge.endpoint, ServerEndpoint(direct.profile))
            XCTAssertEqual(challenge.presented, actual)
            XCTAssertNil(challenge.trusted)
            XCTAssertFalse(failure.allowsReconnect)
        }
    }

    func testUnknownGatewayStopsBeforeForwardingAndDestinationIsAlsoVerified() async throws {
        let fixture = try JumpTestFixture()
        let baseline = try fixture.stats().forwards
        do {
            let session = try await SSHConnectionProvider(hosts: [fixture.gateway]).files(for: fixture.target)
            await session.close()
            XCTFail("An unknown gateway key must stop the route")
        } catch let failure as TerminalConnectionError {
            XCTAssertEqual(failure.hostKeyChallenge?.endpoint, ServerEndpoint(fixture.gateway.profile))
            XCTAssertFalse(failure.allowsReconnect)
        }
        try await fixture.waitClosed()
        XCTAssertEqual(try fixture.stats().forwards, baseline)
        let oldKey = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("Previously trusted key".utf8))
        let gatewayVerifier = fixture.hostKeyVerifier
        let provider = SSHConnectionProvider(hosts: [fixture.gateway]) { endpoint, presented in
            if endpoint == ServerEndpoint(fixture.target.profile) {
                throw HostKeyChallenge(endpoint: endpoint, presented: presented, trusted: oldKey)
            }
            try gatewayVerifier(endpoint, presented)
        }
        do {
            let session = try await provider.files(for: fixture.target)
            await session.close()
            XCTFail("A changed destination key must stop the route")
        } catch let failure as TerminalConnectionError {
            XCTAssertEqual(failure.hostKeyChallenge?.endpoint, ServerEndpoint(fixture.target.profile))
            XCTAssertEqual(failure.hostKeyChallenge?.trusted, oldKey)
            XCTAssertFalse(failure.allowsReconnect)
        }
        try await fixture.waitClosed()
        XCTAssertGreaterThan(try fixture.stats().forwards, baseline)
        XCTAssertEqual(try fixture.stats().shells, 0)
    }
}
