import FarportCore
import Foundation
import XCTest

final class ServerTrustTests: XCTestCase {
    func testFirstUseRequiresExplicitTrustAndChangedKeyCannotReplacePin() throws {
        let secrets = TestSecretStore()
        let repository = KnownHostRepository(secrets: secrets)
        let endpoint = ServerEndpoint(hostname: "SERVER.internal", port: 2222)
        let first = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("abc".utf8))
        let other = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("other".utf8))
        XCTAssertEqual(first.fingerprint, "SHA256:ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0")
        XCTAssertThrowsError(try repository.verify(endpoint, key: first)) { error in
            XCTAssertNil((error as? HostKeyChallenge)?.trusted)
        }
        XCTAssertTrue(secrets.snapshot.isEmpty)
        let request = HostKeyChallenge(endpoint: endpoint, presented: first)
        try repository.trust(request)
        try repository.trust(request)
        XCTAssertNoThrow(try repository.verify(ServerEndpoint(hostname: "server.internal", port: 2222), key: first))
        XCTAssertThrowsError(try repository.verify(endpoint, key: other)) { error in
            XCTAssertEqual((error as? HostKeyChallenge)?.trusted, first)
        }
        XCTAssertThrowsError(try repository.trust(HostKeyChallenge(endpoint: endpoint, presented: other)))
        let changed = HostKeyChallenge(endpoint: endpoint, presented: other, trusted: first)
        XCTAssertThrowsError(try repository.trust(changed))
        XCTAssertEqual(try repository.key(for: endpoint), first)
        XCTAssertThrowsError(try repository.verify(ServerEndpoint(hostname: endpoint.hostname, port: 22), key: first))
        XCTAssertThrowsError(try repository.forget(endpoint, expected: other))
        try repository.forget(endpoint, expected: first)
        XCTAssertNil(try repository.key(for: endpoint))
    }

    func testTrustErrorsNeverAutomaticallyReconnectIncludingProxyJumpContext() {
        let challenge = HostKeyChallenge(endpoint: ServerEndpoint(hostname: "gateway", port: 22),
                                          presented: ServerHostKey(algorithm: "ssh-ed25519", wireData: Data()))
        let error = TerminalConnectionError.route(stage: "Jump host", cause: .serverTrust(challenge))
        XCTAssertFalse(error.allowsReconnect)
        XCTAssertEqual(error.hostKeyChallenge, challenge)
    }

    func testLocalNetworkPermissionIsTypedAndSurvivesRouteContext() {
        let error = TerminalConnectionError.route(stage: "Gateway", cause: .localNetworkPermission)
        XCTAssertTrue(error.requiresLocalNetworkPermission)
        XCTAssertFalse(error.allowsReconnect)
        XCTAssertFalse(error.localizedDescription.contains("Connection lost"))
    }
}
