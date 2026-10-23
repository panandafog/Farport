import HarborCore
import XCTest

final class SyncedProfileImportTests: XCTestCase {
    func testNewRemoteHostHasExplicitlyUnconfiguredLocalCredentials() throws {
        let profile = HostProfile(hostname: "server", username: "user")
        let host = try XCTUnwrap(SyncedProfileImport.apply([profile], to: []).first)
        XCTAssertFalse(host.credentialsConfigured)
        XCTAssertThrowsError(try host.validate())
        XCTAssertEqual(host.credentials, HostCredentials())
    }

    func testMetadataEditsKeepCredentialsButEndpointChangesRequireLocalApproval() throws {
        let original = SavedHost(profile: HostProfile(hostname: "server", username: "user"),
                                 credentials: HostCredentials(password: "local-secret"))
        var profile = original.profile
        profile.name = "Renamed in iCloud"
        let renamed = try XCTUnwrap(SyncedProfileImport.apply([profile], to: [original]).first)
        XCTAssertTrue(renamed.credentialsConfigured)
        XCTAssertEqual(renamed.credentials, original.credentials)
        profile.hostname = "other-server"
        let changed = try XCTUnwrap(SyncedProfileImport.apply([profile], to: [original]).first)
        XCTAssertFalse(changed.credentialsConfigured)
        XCTAssertThrowsError(try changed.validate())
    }

    func testUnconfiguredStateSurvivesKeychainPersistenceWithoutTreatingMissingItemsAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TestSecretStore()
        let repository = ProtectedHostRepository(url: directory.appendingPathComponent("hosts.json"), secrets: store)
        let host = SavedHost(profile: HostProfile(hostname: "server", username: "user"), credentialsConfigured: false)
        try repository.save([host])
        XCTAssertEqual(try repository.load(), [host])
        for key in store.snapshot.keys { store.remove(key) }
        XCTAssertThrowsError(try repository.load())
    }
}
