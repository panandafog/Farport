@testable import Harbor
import HarborCore
import XCTest

@MainActor
final class ConnectionAccessTests: XCTestCase {
    func testGrantContinuesTheOriginalTerminalAttemptOnceAndKeepsHistory() async throws {
        let provider = AccessTestProvider()
        let model = TerminalModel(host: SavedHost(), provider: provider)
        defer { model.disconnect() }
        let view = model.view
        view.feed(text: "before-permission")
        model.connect()
        try await wait { model.state == .waitingForAccess }
        XCTAssertNil(model.error)
        XCTAssertNil(model.requirement)
        XCTAssertNil(model.endedAt)
        await provider.resolve(true)
        try await wait { model.state == .connected }
        XCTAssertTrue(model.view === view)
        XCTAssertTrue(String(data: view.getTerminal().getBufferAsData(), encoding: .utf8)?.contains(
            "before-permission") == true)
        let counts = await provider.counts
        XCTAssertEqual(counts.attempts, 2)
        XCTAssertEqual(counts.waits, 1)
    }

    func testASecondDenialStopsInsteadOfWaitingOrRetryingAgain() async throws {
        let provider = AccessTestProvider(alwaysDenied: true)
        let model = TerminalModel(host: SavedHost(), provider: provider)
        defer { model.disconnect() }
        model.connect()
        try await wait { model.state == .waitingForAccess }
        await provider.resolve(true)
        try await wait { model.requirement != nil }
        try await Task.sleep(for: .milliseconds(30))
        let counts = await provider.counts
        XCTAssertEqual(counts.attempts, 2)
        XCTAssertEqual(counts.waits, 1)
        XCTAssertEqual(model.state, .disconnected)
        XCTAssertNil(model.error)
    }

    func testCancellingTerminalWaitIgnoresALateGrant() async throws {
        let provider = AccessTestProvider()
        let model = TerminalModel(host: SavedHost(), provider: provider)
        model.connect()
        try await wait { model.state == .waitingForAccess }
        model.disconnect()
        await provider.resolve(true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.state, .disconnected)
        XCTAssertEqual(model.endReason, "Connection cancelled")
        XCTAssertNil(model.requirement)
        let counts = await provider.counts
        XCTAssertEqual(counts.attempts, 1)
    }

    func testAnExpiredWaitLeavesAManualRequirementWithoutRetry() async throws {
        let provider = AccessTestProvider()
        let model = TerminalModel(host: SavedHost(), provider: provider)
        defer { model.disconnect() }
        model.connect()
        try await wait { model.state == .waitingForAccess }
        await provider.resolve(false)
        try await wait { model.requirement != nil }
        let counts = await provider.counts
        XCTAssertEqual(counts.attempts, 1)
        XCTAssertNil(model.endedAt)
    }

    func testAFreshTransportErrorReplacesTheOldPermissionRequirement() async throws {
        let provider = AccessTestProvider(afterWaitError: .transport("Connection refused"))
        let model = TerminalModel(host: SavedHost(), provider: provider)
        defer { model.disconnect() }
        model.connect()
        try await wait { model.state == .waitingForAccess }
        await provider.resolve(true)
        try await wait { model.error != nil }
        XCTAssertNil(model.requirement)
        XCTAssertTrue(model.error?.contains("Connection refused") == true)
        let counts = await provider.counts
        XCTAssertEqual(counts.attempts, 2)
        XCTAssertEqual(counts.waits, 1)
    }

    func testFilesContinueAfterAGrant() async throws {
        let provider = AccessTestProvider()
        let model = FilesModel(host: SavedHost(), provider: provider)
        defer { model.disconnect() }
        model.connect()
        try await wait { model.waitingForAccess }
        XCTAssertTrue(model.busy)
        XCTAssertNil(model.requirement)
        await provider.resolve(true)
        try await wait { model.connected }
        XCTAssertFalse(model.waitingForAccess)
        XCTAssertFalse(model.busy)
        let counts = await provider.counts
        XCTAssertEqual(counts.attempts, 2)
    }

    func testCancellingFilesWaitIsImmediateAndIgnoresALateGrant() async throws {
        let provider = AccessTestProvider()
        let model = FilesModel(host: SavedHost(), provider: provider)
        model.connect()
        try await wait { model.waitingForAccess }
        model.cancel()
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.waitingForAccess)
        await provider.resolve(true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(model.connected)
        XCTAssertNil(model.requirement)
        let counts = await provider.counts
        XCTAssertEqual(counts.attempts, 1)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}

private actor AccessTestProvider: ConnectionProvider {
    private let access = AsyncStream<Bool>.makeStream()
    private let alwaysDenied: Bool
    private let afterWaitError: TerminalConnectionError?
    private var attempts = 0
    private var waits = 0
    var counts: (attempts: Int, waits: Int) { (attempts, waits) }

    init(alwaysDenied: Bool = false, afterWaitError: TerminalConnectionError? = nil) {
        self.alwaysDenied = alwaysDenied
        self.afterWaitError = afterWaitError
    }
    func resolve(_ available: Bool) { access.continuation.yield(available); access.continuation.finish() }
    func waitForAccess(for host: SavedHost) async -> Bool {
        waits += 1
        for await available in access.stream { return !Task.isCancelled && available }
        return false
    }

    private func check() throws {
        attempts += 1
        if attempts == 1 || alwaysDenied { throw TerminalConnectionError.localNetworkPermission }
        if let afterWaitError { throw afterWaitError }
    }

    func terminal(for host: SavedHost, sessionID: UUID) throws -> any TerminalSession {
        try check()
        return AccessTestTerminal()
    }

    func files(for host: SavedHost) throws -> any RemoteFileSession {
        try check()
        return AccessTestFiles()
    }
}

private actor AccessTestTerminal: TerminalSession {
    private let output = AsyncStream<Data>.makeStream()
    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        for await data in output.stream { await onOutput(data) }
    }
    func send(_ data: Data) {}
    func resize(_ size: TerminalSize) {}
    func checkConnection(timeout: TimeInterval) {}
    func close() { output.continuation.finish() }
}

private actor AccessTestFiles: RemoteFileSession {
    func canonicalPath(_ path: String) -> String { "/" }
    func list(_ path: String) -> [RemoteEntry] { [] }
    func createDirectory(_ path: String) {}
    func rename(_ path: String, to destination: String) {}
    func remove(_ entry: RemoteEntry) {}
    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) {}
    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) {}
    func close() {}
}
