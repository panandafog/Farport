import FarportCore
@testable import FarportSSH
import XCTest

final class ProxyJumpTests: XCTestCase {
    func testPTYInputResizeAndRemoteDNSWithoutGatewayShell() async throws {
        let fixture = try JumpTestFixture()
        let session = try await fixture.provider.terminal(for: fixture.target)
        let output = JumpOutput()
        let task = Task {
            try await session.run(size: TerminalSize(), onReady: {
                try? await session.resize(TerminalSize(columns: 121, rows: 43))
                try? await session.send(Data("echo jump-terminal-ok\nstty size\n".utf8))
            }, onOutput: { await output.append($0) })
        }
        do {
            try await fixture.wait {
                let text = await output.text
                return text.contains("jump-terminal-ok") && text.contains("43 121")
            }
            try await session.checkConnection(timeout: 1)
            await session.close()
            task.cancel()
            _ = await task.result
            try await fixture.waitClosed()
            let stats = try fixture.stats()
            XCTAssertEqual(stats.shells, 0)
            XCTAssertTrue(stats.destinations.contains("build.internal"))
        } catch { await session.close(); task.cancel(); _ = await task.result; throw error }
    }

    func testSFTPBinaryRoundTripUsesFinalServer() async throws {
        let fixture = try JumpTestFixture()
        let session = try await fixture.provider.files(for: fixture.target)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        let destination = directory.appendingPathComponent("download.bin")
        let bytes = Data((0..<180_000).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        let path = "/jump-\(UUID().uuidString).bin"
        do {
            try await session.upload(source, to: path) { _, _ in }
            try await session.download(path, to: destination) { _, _ in }
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
            let entries = try await session.list("/")
            try await session.remove(try XCTUnwrap(entries.first { $0.path == path }))
            await session.close()
            try await fixture.waitClosed()
        } catch { await session.close(); throw error }
    }

    func testDifferentPrivateKeysForGatewayAndDestination() async throws {
        let fixture = try JumpTestFixture()
        var gateway = fixture.gateway
        var target = fixture.target
        gateway.profile.authentication = .privateKey
        target.profile.authentication = .privateKey
        gateway.credentials.privateKey = try fixture.key("jump-ed25519")
        target.credentials.privateKey = try fixture.key("ed25519")
        let session = try await FixtureTrust.provider(hosts: [gateway]).files(for: target)
        do {
            let entries = try await session.list("/")
            XCTAssertTrue(entries.contains { $0.name == "hello.txt" })
            await session.close()
            try await fixture.waitClosed()
        } catch { await session.close(); throw error }
    }

    func testNestedGatewayChainAndIndependentConnectionCleanup() async throws {
        let fixture = try JumpTestFixture()
        var inner = fixture.gateway
        inner.profile.id = UUID()
        inner.profile.hostname = "gateway.internal"
        inner.profile.jumpHostIDs = [fixture.gateway.id]
        var target = fixture.target
        target.profile.jumpHostIDs = [inner.id]
        let first = try await FixtureTrust.provider(hosts: [fixture.gateway, inner]).files(for: target)
        do {
            let second = try await fixture.provider.files(for: fixture.target)
            do {
                try await first.checkListing()
                await first.close()
                try await fixture.wait { try fixture.stats().active == 1 }
                try await second.checkListing()
                await second.close()
                try await fixture.waitClosed()
                XCTAssertEqual(try fixture.stats().shells, 0)
            } catch { await second.close(); throw error }
        } catch { await first.close(); throw error }
    }

    func testAuthenticationAndForwardingFailuresNameTheirStageAndReleaseParents() async throws {
        let fixture = try JumpTestFixture()
        var gateway = fixture.gateway
        gateway.credentials.password = "incorrect"
        try await assertFailure(fixture, gateway: gateway, target: fixture.target, stage: "Jump host")
        var target = fixture.target
        target.credentials.password = "incorrect"
        try await assertFailure(fixture, gateway: fixture.gateway, target: target, stage: "Destination")
        gateway = fixture.gateway
        gateway.profile.username = "jump-denied"
        try await assertFailure(fixture, gateway: gateway, target: fixture.target, stage: "TCP forwarding")
        target = fixture.target
        target.profile.hostname = "unavailable.internal"
        try await assertFailure(fixture, gateway: fixture.gateway, target: target, stage: "reachability")
    }

    func testStalledDestinationTimesOutAndClosesGateway() async throws {
        let fixture = try JumpTestFixture()
        var target = fixture.target
        target.profile.hostname = "stalled.internal"
        target.profile.port = fixture.stallPort
        let connector = SSHRouteConnector(hosts: [fixture.gateway], timeout: 0.25,
                                          hostKeyVerifier: try FixtureTrust.verifier())
        do {
            let connection = try await connector.connect(target)
            await connection.close()
            XCTFail("Stalled authentication should time out")
        } catch let error as TerminalConnectionError {
            XCTAssertTrue(error.allowsReconnect)
            XCTAssertTrue(error.localizedDescription.contains("Timed out"))
        }
        try await fixture.waitClosed()
    }

    func testUnansweredForwardRequestHasDeadlineAndReleasesGateway() async throws {
        let fixture = try JumpTestFixture()
        var gateway = fixture.gateway
        gateway.profile.username = "jump-silent"
        let connector = SSHRouteConnector(hosts: [gateway], timeout: 0.25,
                                          hostKeyVerifier: try FixtureTrust.verifier())
        do {
            let connection = try await connector.connect(fixture.target)
            await connection.close()
            XCTFail("Unanswered forwarding must time out")
        } catch let error as TerminalConnectionError {
            XCTAssertTrue(error.allowsReconnect)
            XCTAssertTrue(error.localizedDescription.contains("Timed out"))
        }
        try await fixture.waitClosed()
    }

    func testCancellationBeforeInitialSSHHandshakeCompletesPromptly() async throws {
        let fixture = try JumpTestFixture()
        var gateway = fixture.gateway
        gateway.profile.port = fixture.stallPort
        let task = Task { try await FixtureTrust.provider(hosts: [gateway]).files(for: fixture.target) }
        try await Task.sleep(for: .milliseconds(100))
        let cancelled = ContinuousClock.now
        task.cancel()
        do {
            let session = try await task.value
            await session.close()
            XCTFail("Initial SSH connection must cancel")
        } catch is CancellationError {
            XCTAssertLessThan(cancelled.duration(to: .now), .seconds(1))
        }
        try await fixture.waitClosed()
    }

    func testCancellationDuringJumpHandshakeClosesWholeRoute() async throws {
        let fixture = try JumpTestFixture()
        var target = fixture.target
        target.profile.hostname = "stalled.internal"
        target.profile.port = fixture.stallPort
        let before = try fixture.stats().forwards
        let task = Task { try await fixture.provider.files(for: target) }
        try await fixture.wait { try fixture.stats().forwards > before }
        task.cancel()
        do {
            let session = try await task.value
            await session.close()
            XCTFail("Cancelled route must not be returned")
        } catch is CancellationError {
            // Cancelling the parent transport unblocks the nested handshake.
        }
        try await fixture.waitClosed()
    }

    private func assertFailure(_ fixture: JumpTestFixture, gateway: SavedHost, target: SavedHost,
                               stage: String) async throws {
        do {
            let session = try await FixtureTrust.provider(hosts: [gateway]).files(for: target)
            await session.close()
            XCTFail("The configured failure must not fall back to a direct connection")
        } catch let error as TerminalConnectionError {
            XCTAssertTrue(error.localizedDescription.contains(stage), error.localizedDescription)
            XCTAssertFalse(error.allowsReconnect)
        }
        try await fixture.waitClosed()
    }
}

private extension RemoteFileSession {
    func checkListing() async throws {
        let entries = try await list("/")
        XCTAssertTrue(entries.contains { $0.name == "hello.txt" })
    }
}

private actor JumpOutput {
    private var bytes = Data()
    var text: String { String(data: bytes, encoding: .utf8) ?? "" }
    func append(_ data: Data) { bytes.append(data) }
}
