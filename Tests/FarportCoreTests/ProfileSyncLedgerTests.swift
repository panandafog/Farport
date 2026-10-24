import FarportCore
import XCTest

final class ProfileSyncLedgerTests: XCTestCase {
    private let firstDevice = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    private let secondDevice = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()

    private func profile(_ name: String = "Host") -> HostProfile {
        HostProfile(name: name, hostname: "host.internal", username: "user")
    }

    private func pair(_ profiles: [HostProfile]) throws -> (ProfileSyncLedger, ProfileSyncLedger) {
        var first = ProfileSyncLedger(deviceID: firstDevice)
        try first.bootstrap(profiles)
        var second = ProfileSyncLedger(deviceID: secondDevice)
        for value in first.records.values { try second.merge(value); first.acknowledge(value) }
        try second.applied(profiles)
        return (first, second)
    }

    func testIndependentOfflineEditsMergeWithoutReplacingTheWholeLibrary() throws {
        let original = [profile("One"), profile("Two")]
        var (first, second) = try pair(original)
        var left = original; left[0].name = "Edited on first"
        var right = original; right[1].name = "Edited on second"
        try first.localChanged(left)
        try second.localChanged(right)
        let leftRecords = first.records
        for record in second.records.values { try first.merge(record) }
        for record in leftRecords.values { try second.merge(record) }
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(Set(first.profiles.map(\.name)), ["Edited on first", "Edited on second"])
    }

    func testConcurrentSameHostEditsConvergeAndArchiveTheLosingVersion() throws {
        let original = profile()
        var (first, second) = try pair([original])
        var left = original; left.name = "Left"
        var right = original; right.name = "Right"
        try first.localChanged([left]); try second.localChanged([right])
        let leftRecord = try XCTUnwrap(first.records[original.id])
        let rightRecord = try XCTUnwrap(second.records[original.id])
        try first.merge(rightRecord); try second.merge(leftRecord)
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(first.profiles.first?.name, "Right")
        XCTAssertEqual(first.conflicts.first?.profile?.name, "Left")
        XCTAssertEqual(second.conflicts.first?.profile?.name, "Left")
        try first.merge(rightRecord)
        XCTAssertEqual(first.conflicts.count, 1)
    }

    func testDeleteWinsOverANewerOfflineEditAndCannotResurrectTheSameID() throws {
        let original = profile()
        var (first, second) = try pair([original])
        try first.localChanged([])
        var edited = original
        for index in 0..<20 { edited.name = "Offline \(index)"; try second.localChanged([edited]) }
        let deletion = try XCTUnwrap(first.records[original.id])
        let edit = try XCTUnwrap(second.records[original.id])
        try first.merge(edit); try second.merge(deletion)
        XCTAssertTrue(first.profiles.isEmpty)
        XCTAssertTrue(second.profiles.isEmpty)
        XCTAssertEqual(first.records, second.records)
        edited.name = "Still editing an unapplied deletion"
        try second.localChanged([edited])
        XCTAssertTrue(second.profiles.isEmpty)
        XCTAssertTrue(second.conflicts.contains { $0.profile?.name == edited.name })
        var recovered = edited; recovered.id = UUID()
        try second.localChanged([recovered])
        XCTAssertEqual(second.profiles, [recovered])
    }

    func testOldAcknowledgmentCannotClearANewerPendingEdit() throws {
        var ledger = ProfileSyncLedger()
        var host = profile()
        try ledger.bootstrap([host])
        let first = try XCTUnwrap(ledger.records[host.id])
        host.name = "New edit while sending"
        try ledger.localChanged([host])
        ledger.acknowledge(first)
        XCTAssertTrue(ledger.pending.contains(host.id))
        let current = try XCTUnwrap(ledger.records[host.id])
        ledger.acknowledge(current)
        XCTAssertFalse(ledger.pending.contains(host.id))
    }

    func testFirstEnablePreservesCloudProfileAndRecoversDifferingUnversionedLocalCopy() throws {
        var (server, _) = try pair([profile()])
        let current = try XCTUnwrap(server.profiles.first)
        var local = current; local.name = "Older copied JSON"
        var newcomer = ProfileSyncLedger()
        for record in server.records.values { try newcomer.merge(record) }
        try newcomer.bootstrap([local])
        XCTAssertEqual(newcomer.profiles, [current])
        XCTAssertEqual(newcomer.conflicts.first?.profile, local)
        XCTAssertTrue(newcomer.pending.isEmpty)
        try server.localChanged([])
        var other = ProfileSyncLedger()
        for record in server.records.values { try other.merge(record) }
        try other.bootstrap([local])
        XCTAssertTrue(other.profiles.isEmpty)
    }

    func testEditingAnUnappliedRemoteChangeKeepsTheRemoteVersionForRecovery() throws {
        let host = profile()
        var (first, second) = try pair([host])
        var remote = host; remote.name = "Remote edit"
        try first.localChanged([remote])
        try second.merge(try XCTUnwrap(first.records[host.id]))
        var local = host; local.notes = "Edited before reviewing the remote change"
        try second.localChanged([local])
        XCTAssertEqual(second.profiles, [local])
        XCTAssertTrue(second.conflicts.contains { $0.profile == remote })
    }

    func testJournalRoundTripPreservesTombstonesPendingChangesAndBaselines() throws {
        let host = profile()
        var ledger = ProfileSyncLedger()
        try ledger.bootstrap([host]); try ledger.localChanged([])
        let restored = try JSONDecoder().decode(ProfileSyncLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.records, ledger.records)
        XCTAssertEqual(restored.pending, ledger.pending)
        XCTAssertEqual(restored.baseline, ledger.baseline)
        XCTAssertTrue(restored.profiles.isEmpty)
    }
}
