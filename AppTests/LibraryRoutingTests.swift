@testable import Farport
import FarportCore
import XCTest

@MainActor
final class LibraryRoutingTests: XCTestCase {
    func testSavingCycleOrMissingJumpDoesNotChangeHostLibrary() throws {
        let storage = try RoutingStorage()
        defer { storage.remove() }
        let model = storage.library()
        defer { model.closeAll() }
        var gateway = storage.gateway
        gateway.profile.jumpHostIDs = [storage.target.id]
        XCTAssertThrowsError(try model.save(gateway))
        XCTAssertEqual(try storage.repository.load(), storage.hosts)
        var target = storage.target
        target.profile.jumpHostIDs = [UUID()]
        XCTAssertThrowsError(try model.save(target))
        XCTAssertEqual(try storage.repository.load(), storage.hosts)
    }

    func testDeletingJumpHostIsBlockedWithoutSilentlySwitchingToDirect() throws {
        let storage = try RoutingStorage()
        defer { storage.remove() }
        let model = storage.library()
        defer { model.closeAll() }
        model.delete(storage.gateway)
        XCTAssertTrue(model.error?.contains("Target") == true)
        XCTAssertEqual(try storage.repository.load(), storage.hosts)
        var target = storage.target
        target.profile.jumpHostIDs = []
        try model.save(target)
        model.error = nil
        model.delete(storage.gateway)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.hosts.map(\.id), [storage.target.id, storage.independent.id])
    }

    func testGatewayEditRefreshesDependentRouteButPreservesTabsAndUnrelatedWorkspace() throws {
        let storage = try RoutingStorage()
        defer { storage.remove() }
        let model = storage.library()
        defer { model.closeAll() }
        model.selection = storage.independent.id
        let independent = model.selectedWorkspace
        model.selection = storage.target.id
        let previous = try XCTUnwrap(model.selectedWorkspace)
        let tab = previous.addTerminal()
        previous.renameTerminal(tab, title: "Build logs")
        let terminal = try XCTUnwrap(previous.terminal)
        terminal.view.feed(text: "preserved-output-before-gateway-edit")
        var gateway = storage.gateway
        gateway.profile.name = "Renamed gateway"
        gateway.credentials.password = "changed"
        try model.save(gateway)
        model.selection = storage.target.id
        let refreshed = try XCTUnwrap(model.selectedWorkspace)
        XCTAssertTrue(refreshed === previous)
        XCTAssertTrue(refreshed.terminal === terminal)
        let history = String(data: terminal.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(history.contains("preserved-output-before-gateway-edit"))
        XCTAssertEqual(refreshed.tabs, previous.tabs)
        XCTAssertEqual(refreshed.selectedTerminalID, tab)
        XCTAssertEqual(refreshed.terminal?.state, .disconnected)
        XCTAssertEqual(refreshed.routeSummary, "via Renamed gateway")
        model.selection = storage.independent.id
        XCTAssertTrue(model.selectedWorkspace === independent)
        XCTAssertEqual(try storage.repository.load().first?.credentials.password, "changed")
    }

    func testRoutedHostRestoresWithoutConnectingAndCanRepairMissingReference() throws {
        let storage = try RoutingStorage()
        defer { storage.remove() }
        let model = storage.library()
        model.selection = storage.target.id
        model.selectedWorkspace?.addTerminal()
        model.closeAll()
        let restored = storage.library()
        defer { restored.closeAll() }
        XCTAssertEqual(restored.selectedWorkspace?.routeSummary, "via Gateway")
        XCTAssertEqual(restored.selectedWorkspace?.tabs.count, 2)
        XCTAssertEqual(restored.selectedWorkspace?.terminal?.state, .disconnected)
        try storage.repository.save([storage.target])
        let missing = storage.library()
        defer { missing.closeAll() }
        XCTAssertEqual(missing.selectedWorkspace?.routeSummary, "ProxyJump route unavailable")
        var repaired = storage.target
        repaired.profile.jumpHostIDs = []
        try missing.save(repaired)
        XCTAssertNil(missing.selectedWorkspace?.routeSummary)
    }
}

@MainActor
private struct RoutingStorage {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gateway = SavedHost(profile: HostProfile(name: "Gateway", hostname: "jump.test", username: "jump"))
    let target: SavedHost
    let independent = SavedHost(profile: HostProfile(hostname: "direct.test", username: "test"))
    var hosts: [SavedHost] { [gateway, target, independent] }
    var repository: JSONHostRepository { JSONHostRepository(url: root.appendingPathComponent("hosts.json")) }

    init() throws {
        target = SavedHost(profile: HostProfile(name: "Target", hostname: "target.test", username: "test",
                                                jumpHostIDs: [gateway.id]))
        try repository.save(hosts)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func library() -> LibraryModel {
        LibraryModel(repository: repository,
                     workspaceRepository: JSONWorkspaceRepository(url: root.appendingPathComponent("workspace.json")))
    }
}
