@testable import Farport
import FarportCore
import XCTest

@MainActor
final class ServerTrustModelTests: XCTestCase {
    func testOnlyExplicitTrustAndConnectRunsItsContinuationOnce() throws {
        let model = ServerTrustModel(secrets: TestSecretStore())
        let key = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("key".utf8))
        let challenge = HostKeyChallenge(endpoint: ServerEndpoint(hostname: "test", port: 22), presented: key)
        var attempts = 0
        model.present(challenge, retry: { attempts += 1 })
        XCTAssertEqual(attempts, 0)
        model.trust(challenge, continueConnection: true)
        model.trust(challenge, continueConnection: true)
        XCTAssertEqual(attempts, 0)
        model.nextChallenge()
        model.nextChallenge()
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(try model.storedKey(challenge.endpoint), key)
    }

    func testCancelDiscardsContinuationAndFutureOnlyTrustDoesNotConnect() {
        let model = ServerTrustModel(secrets: TestSecretStore())
        let key = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("key".utf8))
        let challenge = HostKeyChallenge(endpoint: ServerEndpoint(hostname: "test", port: 22), presented: key)
        var attempts = 0
        model.present(challenge, retry: { attempts += 1 })
        model.cancelChallenge()
        model.present(challenge)
        XCTAssertFalse(model.canContinue)
        model.trust(challenge)
        XCTAssertEqual(attempts, 0)
    }

    func testPromptDeduplicationExplicitTrustAndChangedKeyReset() throws {
        let secrets = TestSecretStore()
        let model = ServerTrustModel(secrets: secrets)
        let endpoint = ServerEndpoint(hostname: "host", port: 22)
        let first = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("first".utf8))
        let challenge = HostKeyChallenge(endpoint: endpoint, presented: first)
        model.present(challenge)
        model.present(challenge)
        XCTAssertEqual(model.challenge, challenge)
        model.trust(challenge)
        model.nextChallenge()
        XCTAssertNil(model.challenge)
        XCTAssertEqual(try model.storedKey(endpoint), first)
        model.showKeys(hosts: [SavedHost(profile: HostProfile(hostname: "host"))])
        XCTAssertEqual(model.keys[endpoint], first)
        model.showingKeys = false
        let changed = HostKeyChallenge(endpoint: endpoint,
            presented: ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("changed".utf8)), trusted: first)
        model.present(changed)
        model.trust(changed)
        XCTAssertEqual(try model.storedKey(endpoint), first)
        XCTAssertNotNil(model.error)
        model.forget(endpoint, key: first)
        XCTAssertNil(try model.storedKey(endpoint))
        XCTAssertNil(model.keys[endpoint])
        XCTAssertNil(model.challenge)
    }
}
