import HarborCore
import XCTest

final class ConnectionRouteTests: XCTestCase {
    func testDirectAndNestedRoutesPreserveIndependentEndpointCredentials() throws {
        let first = SavedHost(profile: HostProfile(name: "Gateway"), credentials: HostCredentials(password: "one"))
        let second = SavedHost(profile: HostProfile(name: "Inner", jumpHostIDs: [first.id]),
                               credentials: HostCredentials(password: "two"))
        let target = SavedHost(profile: HostProfile(name: "Target", jumpHostIDs: [second.id]),
                               credentials: HostCredentials(password: "three"))
        let route = try ConnectionRoute(to: target, library: [first, second, target])
        XCTAssertEqual(route.hosts.map(\.id), [first.id, second.id, target.id])
        XCTAssertEqual(route.hosts.map { $0.credentials.password }, ["one", "two", "three"])
        XCTAssertEqual(try ConnectionRoute(to: first, library: []).hosts, [first])
        XCTAssertTrue(ConnectionRoute.depends(target, on: first.id, library: [first, second, target]))
    }

    func testExplicitOrderedChainAndEditedTargetOverride() throws {
        let first = SavedHost()
        let second = SavedHost()
        var target = SavedHost()
        let library = [first, second, target]
        target.profile.jumpHostIDs = [first.id, second.id]
        XCTAssertEqual(try ConnectionRoute(to: target, library: library).hosts.map(\.id),
                       [first.id, second.id, target.id])
    }

    func testCyclesRepeatedNodesMissingNodesAndDuplicateHostIDsAreRejected() {
        var first = SavedHost()
        var target = SavedHost(profile: HostProfile(jumpHostIDs: [first.id]))
        first.profile.jumpHostIDs = [target.id]
        XCTAssertThrowsError(try ConnectionRoute(to: target, library: [first, target]))
        first.profile.jumpHostIDs = []
        target.profile.jumpHostIDs = [first.id, first.id]
        XCTAssertThrowsError(try ConnectionRoute(to: target, library: [first]))
        target.profile.jumpHostIDs = [UUID()]
        XCTAssertThrowsError(try ConnectionRoute(to: target, library: [first]))
        XCTAssertThrowsError(try ConnectionRoute(to: target, library: [first, first]))
        XCTAssertFalse(ConnectionRoute.depends(first, on: UUID(), library: [first, target]))
    }

    func testSelfReferenceUnsupportedGatewayAndExcessiveDepthAreRejected() {
        var target = SavedHost()
        target.profile.jumpHostIDs = [target.id]
        XCTAssertThrowsError(try ConnectionRoute(to: target, library: []))
        let gateway = SavedHost(profile: HostProfile(terminalProvider: "other"))
        target.profile.jumpHostIDs = [gateway.id]
        XCTAssertThrowsError(try ConnectionRoute(to: target, library: [gateway]))
        var hosts: [SavedHost] = []
        for _ in 0..<9 { hosts.append(SavedHost(profile: HostProfile(jumpHostIDs: hosts.last.map { [$0.id] } ?? []))) }
        if let last = hosts.last { XCTAssertThrowsError(try ConnectionRoute(to: last, library: hosts)) }
    }

    func testSchemaTwoLoadsDirectAndSchemaThreePreservesRouteReferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hosts.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let gateway = SavedHost()
        let target = SavedHost(profile: HostProfile(jumpHostIDs: [gateway.id]))
        let repository = JSONHostRepository(url: url)
        try repository.save([gateway, target])
        XCTAssertEqual(try repository.load(), [gateway, target])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(gateway)) as? [String: Any])
        var profile = try XCTUnwrap(legacy["profile"] as? [String: Any])
        profile.removeValue(forKey: "jumpHostIDs")
        legacy["profile"] = profile
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "hosts": [legacy]]).write(to: url)
        XCTAssertTrue(try XCTUnwrap(repository.load().first).profile.jumpHostIDs.isEmpty)
        try Data("{\"schemaVersion\":4,\"hosts\":[]}".utf8).write(to: url)
        XCTAssertThrowsError(try repository.load())
    }

    func testStageContextPreservesRetryPolicy() {
        let transient = TerminalConnectionError.route(stage: "Gateway", cause: .transport("Disconnected"))
        XCTAssertTrue(transient.allowsReconnect)
        XCTAssertTrue(transient.localizedDescription.contains("Gateway"))
        for error in [TerminalConnectionError.authentication, .hostKeyRejected, .configuration("Forwarding denied")] {
            XCTAssertFalse(TerminalConnectionError.route(stage: "Target", cause: error).allowsReconnect)
        }
    }
}
