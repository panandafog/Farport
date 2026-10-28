import FarportCore
import XCTest

final class ProfileTabSyncTests: XCTestCase {
    private func profile(tabs: [TerminalTab]) throws -> HostProfile {
        var layout = SyncedTerminalTabs()
        try layout.record(tabs, device: UUID())
        return HostProfile(hostname: "sync.invalid", username: "test", terminalTabs: layout)
    }

    func testFirstEnableAddsLegacyLocalTabsToExistingCloudProfile() throws {
        let tabs = [TerminalTab(title: "Shell"), TerminalTab(title: "Logs"), TerminalTab(title: "Build")]
        let local = try profile(tabs: tabs)
        var remote = local
        remote.terminalTabs = nil
        remote.name = "Cloud name"
        var server = ProfileSyncLedger()
        try server.bootstrap([remote])
        var newcomer = ProfileSyncLedger()
        for record in server.records.values { try newcomer.merge(record) }
        try newcomer.bootstrap([local])
        XCTAssertEqual(newcomer.profiles.first?.terminalTabs?.tabs, tabs)
        XCTAssertEqual(newcomer.profiles.first?.name, "Cloud name")
        XCTAssertTrue(newcomer.pending.contains(local.id))
        let encoded = try XCTUnwrap(newcomer.records[local.id])
        XCTAssertEqual(encoded.schemaVersion, 2)
        try encoded.validate()
    }

    func testConcurrentSameHostTabAddsConvergeAndDoNotCreateProfileRecoveryNoise() throws {
        let original = try profile(tabs: [TerminalTab(title: "Shell")])
        var first = ProfileSyncLedger()
        try first.bootstrap([original])
        var second = ProfileSyncLedger()
        for record in first.records.values { try second.merge(record); first.acknowledge(record) }
        try second.applied([original])
        var left = original
        var right = original
        let logs = TerminalTab(title: "Logs")
        let build = TerminalTab(title: "Build")
        try left.terminalTabs?.record([original.terminalTabs?.tabs.first].compactMap { $0 } + [logs], device: UUID())
        try right.terminalTabs?.record([original.terminalTabs?.tabs.first].compactMap { $0 } + [build], device: UUID())
        try first.localChanged([left])
        try second.localChanged([right])
        for _ in 0..<3 {
            let incoming = Array(second.records.values)
            for record in first.records.values { try second.merge(record) }
            for record in incoming { try first.merge(record) }
        }
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(first.profiles.first?.terminalTabs?.tabs.count, 3)
        XCTAssertTrue(first.conflicts.isEmpty)
        XCTAssertTrue(second.conflicts.isEmpty)
        try first.validate()
        try second.validate()
    }

    func testEditingSettingsOnAStaleDeviceCannotEraseNewRemoteTabs() throws {
        let original = try profile(tabs: [TerminalTab(title: "Shell")])
        var ledger = ProfileSyncLedger()
        try ledger.bootstrap([original])
        var remote = original
        let extra = TerminalTab(title: "Logs")
        let tabs = (remote.terminalTabs?.tabs ?? []) + [extra]
        try remote.terminalTabs?.record(tabs, device: UUID())
        let record = CloudHostRecord(id: original.id, revision: .init(counter: 10, device: UUID()), profile: remote)
        try ledger.merge(record)
        var stale = original
        stale.notes = "Offline notes"
        try ledger.localChanged([stale])
        XCTAssertEqual(ledger.profiles.first?.notes, "Offline notes")
        XCTAssertTrue(ledger.profiles.first?.terminalTabs?.tabs.contains { $0.id == extra.id } == true)
    }
}
