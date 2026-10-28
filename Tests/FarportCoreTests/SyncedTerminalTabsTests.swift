import FarportCore
import XCTest

final class SyncedTerminalTabsTests: XCTestCase {
    func testConcurrentAddsAndRenamesMergeWithoutLosingEitherTab() throws {
        let initial = TerminalTab(title: "Shell")
        var original = SyncedTerminalTabs()
        try original.record([initial], device: UUID())
        var left = original
        var right = original
        let logs = TerminalTab(title: "Logs")
        let build = TerminalTab(title: "Build")
        var renamed = initial
        renamed.title = "Work"
        try left.record([renamed, logs], device: UUID())
        try right.record([initial, build], device: UUID())
        let merged = try left.merging(right)
        XCTAssertEqual(merged, try right.merging(left))
        XCTAssertEqual(merged, try merged.merging(merged))
        XCTAssertEqual(Set(merged.tabs.map(\.id)), [initial.id, logs.id, build.id])
        XCTAssertEqual(merged.tabs.first?.title, "Work")
    }

    func testClosedTabsStayClosedAfterNewerOfflineEditsAndRoundTrip() throws {
        let tab = TerminalTab(title: "Shell")
        var initial = SyncedTerminalTabs()
        try initial.record([tab], device: UUID())
        var closed = initial
        try closed.record([], device: UUID())
        var offline = initial
        var renamed = tab
        for index in 0..<10 {
            renamed.title = "Offline \(index)"
            try offline.record([renamed], device: UUID())
        }
        let merged = try offline.merging(closed)
        XCTAssertTrue(merged.tabs.isEmpty)
        XCTAssertEqual(merged, try closed.merging(offline))
        let restored = try JSONDecoder().decode(SyncedTerminalTabs.self, from: JSONEncoder().encode(merged))
        XCTAssertEqual(restored, merged)
        let new = TerminalTab(title: "New shell")
        var reopened = restored
        try reopened.record([new], device: UUID())
        XCTAssertEqual(reopened.tabs, [new])
        XCTAssertTrue(reopened.changes.contains { $0.tab.id == tab.id && $0.deleted })
    }

    func testReorderAndRenameRetainUUIDsAndNoOpDoesNotAdvanceRevisions() throws {
        let tabs = [TerminalTab(title: "Shell"), TerminalTab(title: "Logs"), TerminalTab(title: "Build")]
        var layout = SyncedTerminalTabs()
        try layout.record(tabs, device: UUID())
        let original = layout
        try layout.record(tabs, device: UUID())
        XCTAssertEqual(layout, original)
        try layout.record(Array(tabs.reversed()), device: UUID())
        XCTAssertEqual(layout.tabs, Array(tabs.reversed()))
        XCTAssertEqual(Set(layout.tabs.map(\.id)), Set(tabs.map(\.id)))
        XCTAssertThrowsError(try layout.record([tabs[0], tabs[0]], device: UUID()))
    }

    func testRecoveryCopyDoesNotReuseAnyOtherHostsTmuxIdentity() throws {
        var layout = SyncedTerminalTabs()
        let tabs = [TerminalTab(title: "Shell"), TerminalTab(title: "Logs")]
        try layout.record(tabs, device: UUID())
        let id = UUID()
        let copy = try layout.copy(for: id)
        XCTAssertEqual(copy.tabs.map(\.title), tabs.map(\.title))
        XCTAssertEqual(copy.tabs.first?.id, id)
        XCTAssertTrue(Set(copy.tabs.map(\.id)).isDisjoint(with: Set(tabs.map(\.id))))
    }

    func testLegacyWorkspaceGetsAPersistableDeviceIdentityWithoutLosingTabs() throws {
        let workspace = HostWorkspace(hostID: UUID())
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "hosts": [JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace))]
        ])
        let restored = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        XCTAssertEqual(restored.hosts, [workspace])
        let next = try JSONDecoder().decode(WorkspaceSnapshot.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(next.deviceID, restored.deviceID)
    }
}
