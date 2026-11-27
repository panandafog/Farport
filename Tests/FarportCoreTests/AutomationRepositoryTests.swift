import FarportCore
import Foundation
import XCTest

final class AutomationRepositoryTests: XCTestCase {
    func testQueryDoesNotReadSecretsOrRewriteOldProtectedSchemas() throws {
        try withLibrary { repository, secrets, host in
            var document = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(contentsOf: repository.url)
            ) as? [String: Any])
            document["schemaVersion"] = 4
            try JSONSerialization.data(withJSONObject: document).write(to: repository.url)
            let before = try Data(contentsOf: repository.url)
            for account in secrets.snapshot.keys { secrets.remove(account) }
            XCTAssertEqual(try repository.automationProfiles(), [host.profile])
            XCTAssertEqual(try Data(contentsOf: repository.url), before)
            XCTAssertTrue(secrets.snapshot.isEmpty)
            XCTAssertThrowsError(try repository.automationRoute(to: host.id))
            XCTAssertEqual(try Data(contentsOf: repository.url), before)
        }
    }

    func testRouteResolvesOnlyItsOwnSecretsAndRetainsJumpOrdering() throws {
        try withLibrary { repository, secrets, gateway in
            let target = SavedHost(profile: HostProfile(hostname: "target.internal", username: "target-user",
                                                       jumpHostIDs: [gateway.id]),
                                   credentials: HostCredentials(password: "target-secret"))
            let unrelated = SavedHost(profile: HostProfile(hostname: "other", username: "other-user"))
            try repository.save([unrelated, target, gateway])
            struct Document: Decodable { let hosts: [ProtectedHost] }
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: repository.url))
            let account = try XCTUnwrap(document.hosts.first { $0.profile.id == unrelated.id }?.credentialReference)
            secrets.remove(account)
            let before = try Data(contentsOf: repository.url)
            let snapshot = secrets.snapshot
            XCTAssertEqual(try repository.automationRoute(to: target.id).hosts, [gateway, target])
            XCTAssertEqual(try repository.automationProfiles().count, 3)
            XCTAssertEqual(secrets.snapshot, snapshot)
            XCTAssertEqual(try Data(contentsOf: repository.url), before)
        }
    }

    func testUnconfiguredCredentialsMissingHostAndCycleFailWithoutSaving() throws {
        try withLibrary { repository, _, original in
            var host = original
            host.credentialsConfigured = false
            try repository.save([host])
            XCTAssertThrowsError(try repository.automationRoute(to: host.id))
            host.credentialsConfigured = true
            host.profile.jumpHostIDs = [host.id]
            try repository.save([host])
            let before = try Data(contentsOf: repository.url)
            XCTAssertThrowsError(try repository.automationRoute(to: host.id))
            XCTAssertThrowsError(try repository.automationRoute(to: UUID()))
            XCTAssertEqual(try Data(contentsOf: repository.url), before)
        }
    }

    func testLegacyLibraryIsNeverMigratedByShortcuts() throws {
        try withLibrary { repository, secrets, host in
            try JSONHostRepository(url: repository.url).save([host])
            let before = try Data(contentsOf: repository.url)
            let snapshot = secrets.snapshot
            XCTAssertThrowsError(try repository.automationProfiles())
            XCTAssertThrowsError(try repository.automationRoute(to: host.id))
            XCTAssertEqual(try Data(contentsOf: repository.url), before)
            XCTAssertEqual(secrets.snapshot, snapshot)
        }
    }

    func testDuplicateIDsAreRejectedAndAbsentLibraryIsNotCreated() throws {
        try withLibrary { repository, _, host in
            try repository.save([host, host])
            XCTAssertThrowsError(try repository.automationProfiles())
            XCTAssertThrowsError(try repository.automationRoute(to: host.id))
            try FileManager.default.removeItem(at: repository.url)
            XCTAssertTrue(try repository.automationProfiles().isEmpty)
            XCTAssertThrowsError(try repository.automationRoute(to: host.id))
            XCTAssertFalse(FileManager.default.fileExists(atPath: repository.url.path))
        }
    }

    private func withLibrary(_ body: (ProtectedHostRepository, TestSecretStore, SavedHost) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let secrets = TestSecretStore()
        let repository = ProtectedHostRepository(url: root.appendingPathComponent("hosts.json"), secrets: secrets)
        let host = SavedHost(profile: HostProfile(hostname: "gateway", username: "user"),
                             credentials: HostCredentials(password: "secret"))
        try repository.save([host])
        try body(repository, secrets, host)
    }
}
