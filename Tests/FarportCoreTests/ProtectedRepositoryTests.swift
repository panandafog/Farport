import FarportCore
import Foundation
import XCTest

final class ProtectedRepositoryTests: XCTestCase {
    private func host() -> SavedHost {
        SavedHost(profile: HostProfile(hostname: "host", username: "user"),
                  credentials: HostCredentials(password: "secret-password", privateKey: "secret-private-key",
                                                 passphrase: "secret-passphrase"))
    }

    func testLegacyLibraryMigratesOnlyAfterSecretsAreVerifiedAndSurvivesRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hosts.json")
        let secrets = TestSecretStore()
        let original = host()
        try JSONHostRepository(url: url).save([original])
        let repository = ProtectedHostRepository(url: url, secrets: secrets)
        XCTAssertEqual(try repository.load(), [original])
        let json = try String(contentsOf: url, encoding: .utf8)
        for secret in ["secret-password", "secret-private-key", "secret-passphrase"] {
            XCTAssertFalse(json.contains(secret))
        }
        XCTAssertTrue(json.contains("credentialReference"))
        XCTAssertThrowsError(try JSONHostRepository(url: url).load())
        XCTAssertEqual(try ProtectedHostRepository(url: url, secrets: secrets).load(), [original])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testPartialMigrationFailurePreservesOriginalFileAndCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hosts.json")
        let original = [host(), host()]
        try JSONHostRepository(url: url).save(original)
        let before = try Data(contentsOf: url)
        let secrets = TestSecretStore()
        secrets.failInsert(at: 2)
        let repository = ProtectedHostRepository(url: url, secrets: secrets)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try JSONHostRepository(url: url).load(), original)
        secrets.failInsert(at: nil)
        XCTAssertEqual(try repository.load(), original)
    }

    func testCredentialEditsRotateReferencesAndDeletionKeepsOtherLibrariesIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = TestSecretStore()
        let first = ProtectedHostRepository(url: directory.appendingPathComponent("first.json"), secrets: secrets)
        let other = ProtectedHostRepository(url: directory.appendingPathComponent("other.json"), secrets: secrets)
        var value = host()
        try first.save([value])
        try other.save([value])
        let initialReferences = Set(secrets.snapshot.keys)
        value.profile.name = "Renamed"
        try first.save([value])
        XCTAssertEqual(Set(secrets.snapshot.keys), initialReferences)
        value.credentials.password = "changed-password"
        try first.save([value])
        XCTAssertEqual(try first.load(), [value])
        XCTAssertEqual(secrets.snapshot.count, 2)
        try first.save([])
        XCTAssertEqual(secrets.snapshot.count, 1)
        XCTAssertEqual(try other.load(), [hostWithIdentity(of: value)])
    }

    func testMissingKeychainItemNeverBecomesAnEmptyPassword() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = TestSecretStore()
        let url = directory.appendingPathComponent("hosts.json")
        let repository = ProtectedHostRepository(url: url, secrets: secrets)
        try repository.save([host()])
        let bytes = try Data(contentsOf: url)
        for key in secrets.snapshot.keys { secrets.remove(key) }
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testSchemaFourMigrationPreservesReferencesAndExistingCredentialReadiness() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = TestSecretStore()
        let url = directory.appendingPathComponent("hosts.json")
        let repository = ProtectedHostRepository(url: url, secrets: secrets)
        let original = host()
        try repository.save([original])
        let references = secrets.snapshot
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var hosts = try XCTUnwrap(legacy["hosts"] as? [[String: Any]])
        hosts[0].removeValue(forKey: "configured")
        legacy["hosts"] = hosts
        legacy["schemaVersion"] = 4
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        XCTAssertEqual(try repository.load(), [original])
        XCTAssertEqual(secrets.snapshot, references)
        let migrated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(migrated["schemaVersion"] as? Int, 5)
    }

    func testFinderMigrationIsAppOnlyAndKeepsDomainAccessAndRouteIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = TestSecretStore()
        let target = host()
        let location = try FinderLocation(host: target, library: [target], rootPath: "/", access: .readWrite)
        try FinderLocationRepository(directory: directory).save(location)
        let url = directory.appendingPathComponent(location.id.uuidString + ".json")
        let bytes = try Data(contentsOf: url)
        let extensionStore = ProtectedFinderLocationRepository(directory: directory, secrets: secrets)
        XCTAssertThrowsError(try extensionStore.load(location.id))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let appStore = ProtectedFinderLocationRepository(directory: directory, secrets: secrets, migrateLegacy: true)
        XCTAssertEqual(try appStore.load(location.id), location)
        XCTAssertEqual(try extensionStore.load(location.id), location)
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains(target.credentials.password))
        XCTAssertFalse(json.contains(target.credentials.privateKey))
        XCTAssertFalse(json.contains(target.credentials.passphrase))
        try extensionStore.remove(location.id)
        XCTAssertTrue(secrets.snapshot.isEmpty)
        XCTAssertThrowsError(try extensionStore.load(location.id))
    }

    private func hostWithIdentity(of value: SavedHost) -> SavedHost {
        var original = host()
        original.profile.id = value.id
        return original
    }
}
