import FarportCore
import XCTest

final class HostOrderingTests: XCTestCase {
    func testReorderingRoundTripsAndNoOpKeepsRevisions() throws {
        let hosts = (0..<3).map { SavedHost(profile: HostProfile(hostname: "host\($0).invalid", username: "test")) }
        let original = try HostOrdering.record(hosts, device: UUID())
        XCTAssertEqual(try HostOrdering.record(original, device: UUID()), original)
        let reordered = try HostOrdering.record(Array(original.reversed()), device: UUID())
        let restored = try JSONDecoder().decode([SavedHost].self, from: JSONEncoder().encode(reordered))
        XCTAssertEqual(HostOrdering.sorted(restored.map(\.profile)).map(\.id), hosts.reversed().map(\.id))
        XCTAssertEqual(Set(restored.map(\.id)), Set(hosts.map(\.id)))
    }

    func testStaleSettingsEditDoesNotEraseOrderAndOrderDoesNotReplaceSettings() throws {
        let hosts = (0..<3).map { SavedHost(profile: HostProfile(hostname: "host\($0).invalid", username: "test")) }
        let original = try HostOrdering.record(hosts, device: UUID())
        var first = ProfileSyncLedger()
        try first.bootstrap(original.map(\.profile))
        var second = ProfileSyncLedger()
        for record in first.records.values { try second.merge(record) }
        try second.applied(original.map(\.profile))
        let reordered = try HostOrdering.record(Array(original.reversed()), device: UUID())
        try first.localChanged(reordered.map(\.profile))
        var edited = original
        edited[0].profile.notes = "Independent offline edit"
        try second.localChanged(edited.map(\.profile))
        for _ in 0..<3 {
            let incoming = Array(second.records.values)
            for record in first.records.values { try second.merge(record) }
            for record in incoming { try first.merge(record) }
        }
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(first.profiles.map(\.id), reordered.map(\.id))
        XCTAssertEqual(first.profiles.last?.notes, "Independent offline edit")
        let record = try XCTUnwrap(first.records[hosts[0].id])
        XCTAssertEqual(record.schemaVersion, 3)
        try first.validate()
    }

    func testConcurrentOrdersConvergeDeterministically() throws {
        let hosts = (0..<3).map { SavedHost(profile: HostProfile(hostname: "host\($0).invalid", username: "test")) }
        let original = try HostOrdering.record(hosts, device: UUID())
        let left = try HostOrdering.record([original[2], original[0], original[1]], device: UUID())
        let right = try HostOrdering.record([original[1], original[2], original[0]], device: UUID())
        let leftByID = Dictionary(uniqueKeysWithValues: left.map { ($0.id, $0.profile) })
        let rightByID = Dictionary(uniqueKeysWithValues: right.map { ($0.id, $0.profile) })
        for host in original {
            let first = try XCTUnwrap(leftByID[host.id])
            let second = try XCTUnwrap(rightByID[host.id])
            XCTAssertEqual(try first.mergingSyncedMetadata(from: second).position,
                           try second.mergingSyncedMetadata(from: first).position)
        }
    }

    func testReorderBeforeApplyingIncomingSettingsKeepsThoseSettings() throws {
        let hosts = (0..<2).map { SavedHost(profile: HostProfile(hostname: "host\($0).invalid", username: "test")) }
        let original = try HostOrdering.record(hosts, device: UUID())
        var ledger = ProfileSyncLedger()
        try ledger.bootstrap(original.map(\.profile))
        for record in Array(ledger.records.values) { ledger.acknowledge(record) }
        var incoming = original[0].profile
        incoming.hostname = "changed-remotely.invalid"
        let revision = ProfileRevision(counter: 50, device: UUID())
        try ledger.merge(CloudHostRecord(id: incoming.id, revision: revision, profile: incoming,
                                         settingsRevision: revision))
        let reordered = try HostOrdering.record(Array(original.reversed()), device: UUID())
        try ledger.localChanged(reordered.map(\.profile))
        XCTAssertEqual(ledger.profiles.map(\.id), reordered.map(\.id))
        XCTAssertEqual(ledger.profiles.last?.hostname, "changed-remotely.invalid")
        XCTAssertTrue(ledger.conflicts.isEmpty)
    }

    func testListMovesHandleMultipleItemsAndInvalidOffsets() {
        XCTAssertEqual(ItemOrdering.moving([0, 1, 2, 3], from: IndexSet([0, 2]), to: 4), [1, 3, 0, 2])
        XCTAssertEqual(ItemOrdering.moving([0, 1], from: IndexSet(integer: 8), to: 0), [0, 1])
        XCTAssertEqual(ItemOrdering.moving([0, 1], from: [], to: 8), [0, 1])
    }
}
