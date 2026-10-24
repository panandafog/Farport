import FarportCore
import FarportSecurity
import Foundation
import XCTest

final class KeychainTests: XCTestCase {
    func testTestBundleDoesNotAdvertiseItselfAsAFileProvider() {
        XCTAssertNil(Bundle(for: KeychainTests.self).object(forInfoDictionaryKey: "NSExtension"))
    }

    func testAppDeclaresItsLocalNetworkPurpose() throws {
        let purpose = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String
        )
        XCTAssertFalse(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(purpose.contains("SSH"))
        XCTAssertTrue(purpose.contains("SFTP"))
        XCTAssertTrue(purpose.contains("Finder"))
    }

    func testRealSharedKeychainInsertReadDuplicateAndConditionalRemoval() throws {
        let group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "HarborKeychainGroup") as? String)
        let service = "dev.harbor.tests." + UUID().uuidString
        let store = KeychainSecretStore(accessGroup: group, service: service)
        let secondReader = KeychainSecretStore(accessGroup: group, service: service)
        let account = UUID().uuidString
        defer { try? store.remove(account) }
        XCTAssertNil(try store.data(for: account))
        let data = Data("Disposable private key and passphrase".utf8)
        try store.insert(data, for: account)
        XCTAssertEqual(try secondReader.data(for: account), data)
        XCTAssertThrowsError(try store.insert(Data("replacement".utf8), for: account))
        XCTAssertThrowsError(try store.remove(account, matching: Data("stale".utf8)))
        XCTAssertEqual(try store.data(for: account), data)
        try store.remove(account, matching: data)
        XCTAssertNil(try secondReader.data(for: account))
    }

    func testRealKeychainPinsSurviveRepositoryRecreationAndCannotBeSilentlyReplaced() throws {
        let group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "HarborKeychainGroup") as? String)
        let store = KeychainSecretStore(accessGroup: group, service: "dev.harbor.tests." + UUID().uuidString)
        let endpoint = ServerEndpoint(hostname: "disposable-test.invalid", port: 2233)
        let key = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data(UUID().uuidString.utf8))
        let repository = KnownHostRepository(secrets: store)
        defer { try? repository.forget(endpoint, expected: key) }
        try repository.trust(HostKeyChallenge(endpoint: endpoint, presented: key))
        let restarted = KnownHostRepository(secrets: store)
        XCTAssertNoThrow(try restarted.verify(endpoint, key: key))
        let changed = ServerHostKey(algorithm: key.algorithm, wireData: Data("changed".utf8))
        XCTAssertThrowsError(try restarted.verify(endpoint, key: changed))
        try restarted.forget(endpoint, expected: key)
        XCTAssertNil(try repository.key(for: endpoint))
    }

    func testUnentitledKeychainGroupFailsClosed() {
        let store = KeychainSecretStore(accessGroup: "INVALIDTEAM.dev.harbor.unentitled",
                                        service: "dev.harbor.tests." + UUID().uuidString)
        XCTAssertThrowsError(try store.insert(Data("test".utf8), for: UUID().uuidString))
    }
}
