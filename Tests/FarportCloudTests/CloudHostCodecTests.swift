import CloudKit
@testable import FarportCloud
import FarportCore
import XCTest

final class CloudHostCodecTests: XCTestCase {
    func testOnlyEncryptedProfileMetadataIsEncodedAndRoundTripsWithSystemFields() throws {
        var profile = HostProfile(hostname: "host.internal", username: "user", notes: "Private profile metadata")
        var tabs = SyncedTerminalTabs()
        try tabs.record([TerminalTab(id: profile.id, title: "Shell"), TerminalTab(title: "Logs")], device: UUID())
        profile.terminalTabs = tabs
        let value = CloudHostRecord(id: profile.id, revision: .init(counter: 1, device: UUID()), profile: profile)
        let record = try CloudHostCodec.encode(value, fields: nil)
        XCTAssertEqual(Set(record.allKeys()), ["profile"])
        XCTAssertEqual(Set(record.encryptedValues.allKeys()), ["profile"])
        XCTAssertEqual(try CloudHostCodec.decode(record), value)
        let rebuilt = try CloudHostCodec.encode(value, fields: CloudHostCodec.systemFields(record))
        XCTAssertEqual(try CloudHostCodec.decode(rebuilt), value)
        let bytes = try XCTUnwrap(record.encryptedValues["profile"] as? Data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let metadata = try XCTUnwrap(json["profile"] as? [String: Any])
        for forbidden in ["password", "privateKey", "passphrase", "credentialReference", "credentialsConfigured",
                          "selectedTerminalID", "history", "connected"] {
            XCTAssertNil(json[forbidden])
            XCTAssertNil(metadata[forbidden])
        }
    }

    func testInvalidOrFutureRecordAndCorruptStateFailClosed() throws {
        let record = CKRecord(recordType: "FutureRecord", recordID: CloudHostCodec.id(UUID()))
        XCTAssertThrowsError(try CloudHostCodec.decode(record))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        let bytes = Data("{\"schemaVersion\":99}".utf8)
        try bytes.write(to: url)
        XCTAssertThrowsError(try CloudSyncFile(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testOfflineQueuePersistsWithoutCreatingACloudContainerOrTouchingAnAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = CloudSyncFile(url: directory.appendingPathComponent("state.json"))
        let profile = HostProfile(hostname: "offline", username: "user")
        var saved = CloudSyncDocument()
        saved.enabled = true; saved.initialized = true; saved.accountID = "test-account"
        try file.save(saved)
        let service = try CloudHostSync(url: file.url, containerIdentifier: "iCloud.test.invalid", changed: { _ in })
        try await service.localChanged(profiles: [profile])
        let restored = try file.load()
        XCTAssertEqual(restored.ledger.profiles, [profile])
        XCTAssertTrue(restored.ledger.pending.contains(profile.id))
        let engine = await service.engine
        XCTAssertNil(engine)
        try await service.disable()
        XCTAssertFalse(try file.load().enabled)
        XCTAssertEqual(try file.load().ledger.profiles, [profile])
    }

    func testCorruptLedgerClockStopsLoadingWithoutReplacingTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = CloudSyncFile(url: directory.appendingPathComponent("state.json"))
        var saved = CloudSyncDocument()
        try saved.ledger.bootstrap([HostProfile(hostname: "test.invalid", username: "user")])
        let data = try JSONEncoder().encode(saved)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var ledger = try XCTUnwrap(json["ledger"] as? [String: Any])
        ledger["counter"] = 0
        json["ledger"] = ledger
        let corrupted = try JSONSerialization.data(withJSONObject: json)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try corrupted.write(to: file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf: file.url), corrupted)
    }

    func testAccountChangePauseKeepsProfilesAndQueueAndRequiresExplicitReset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = CloudSyncFile(url: directory.appendingPathComponent("state.json"))
        let profile = HostProfile(hostname: "offline", username: "user")
        var saved = CloudSyncDocument()
        saved.enabled = true; saved.initialized = true; saved.accountID = "previous-account"
        try saved.ledger.bootstrap([profile])
        try file.save(saved)
        let service = try CloudHostSync(url: file.url, containerIdentifier: "iCloud.test.invalid", changed: { _ in })
        try await service.pause("Account changed", reset: true)
        let paused = try file.load()
        XCTAssertFalse(paused.enabled)
        XCTAssertTrue(paused.resetRequired)
        XCTAssertEqual(paused.ledger.profiles, [profile])
        XCTAssertEqual(paused.ledger.pending, [profile.id])
    }
}
