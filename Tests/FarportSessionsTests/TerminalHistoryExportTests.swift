import FarportCore
import FarportSessions
import XCTest

@MainActor
final class TerminalHistoryExportTests: XCTestCase {
    func testLocalHistoryWorksBeforeConnectionAndAfterDisconnectWithoutNetworkWork() async throws {
        let session = HistoryTestSession()
        let model = makeModel(session)
        model.screen.write(Data("retained Привет\r\n".utf8))
        let first = try await model.historySnapshot(from: .local)
        XCTAssertEqual(first, "retained Привет\n")
        XCTAssertFalse(model.canReadTmuxHistory)
        model.connect()
        try await waitUntil { model.state == .connected }
        model.disconnect()
        let last = try await model.historySnapshot(from: .local)
        XCTAssertTrue(last.contains("retained Привет"))
        let reads = await session.reads
        XCTAssertEqual(reads, 0)
    }

    func testRemoteHistoryRequiresConnectedTmuxAndDoesNotSendInteractiveInput() async throws {
        let session = HistoryTestSession()
        let model = makeModel(session)
        do { _ = try await model.historySnapshot(from: .tmux); XCTFail("Disconnected export must fail") } catch {}
        model.connect()
        try await waitUntil { model.canReadTmuxHistory }
        let text = try await model.historySnapshot(from: .tmux)
        XCTAssertEqual(text, "server history Привет\n")
        let bytes = await session.sent
        XCTAssertTrue(bytes.isEmpty)
        XCTAssertEqual(model.state, .connected)
        model.disconnect()
        let plain = makeModel(HistoryTestSession(), tmux: false)
        plain.connect()
        try await waitUntil { plain.state == .connected }
        XCTAssertFalse(plain.canReadTmuxHistory)
        plain.disconnect()
    }

    func testOldConnectionCannotCompleteAnExportAfterReconfiguration() async throws {
        for failing in [false, true] {
            let session = HistoryTestSession(delayed: true, failing: failing)
            let model = makeModel(session)
            model.connect()
            try await waitUntil { model.canReadTmuxHistory }
            let request = Task { try await model.historySnapshot(from: .tmux) }
            try await waitUntil { await session.reads == 1 }
            model.reconfigure(host: SavedHost(), provider: HistoryTestProvider(session: HistoryTestSession()))
            await session.finishRead()
            do {
                _ = try await request.value
                XCTFail("Late result must be discarded")
            } catch is CancellationError {} catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testExportFailureLeavesTheTerminalConnectedAndLocalHistoryAvailable() async throws {
        let model = makeModel(HistoryTestSession(failing: true))
        model.connect()
        try await waitUntil { model.canReadTmuxHistory }
        model.screen.write(Data("local history".utf8))
        do { _ = try await model.historySnapshot(from: .tmux); XCTFail("Expected export error") } catch {}
        XCTAssertEqual(model.state, .connected)
        XCTAssertNil(model.error)
        let local = try await model.historySnapshot(from: .local)
        XCTAssertTrue(local.contains("local history"))
        model.disconnect()
    }

    private func makeModel(_ session: HistoryTestSession, tmux: Bool = true) -> RecordingTerminal {
        RecordingTerminal(host: SavedHost(profile: HostProfile(terminalResumeStrategy: tmux ? .tmux : .none)),
                          provider: HistoryTestProvider(session: session))
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw HarborError.message("History test timed out")
    }
}

private struct HistoryTestProvider: ConnectionProvider {
    let session: HistoryTestSession
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession { session }
    func files(for host: SavedHost) async throws -> any RemoteFileSession { throw CancellationError() }
}

private actor HistoryTestSession: TerminalHistorySession {
    let delayed: Bool
    let failing: Bool
    private let output = AsyncStream<Data>.makeStream()
    private var pendingRead: CheckedContinuation<Void, Never>?
    private(set) var reads = 0
    private(set) var sent = Data()

    init(delayed: Bool = false, failing: Bool = false) { self.delayed = delayed; self.failing = failing }
    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        for await data in output.stream { await onOutput(data) }
    }
    func captureHistory() async throws -> String {
        reads += 1
        if delayed { await withCheckedContinuation { pendingRead = $0 } }
        if failing { throw HarborError.message("Capture failed") }
        return "server history Привет\r\n"
    }
    func finishRead() { pendingRead?.resume(); pendingRead = nil }
    func send(_ data: Data) async throws { sent.append(data) }
    func resize(_ size: TerminalSize) async throws {}
    func checkConnection(timeout: TimeInterval) async throws {}
    func close() async { output.continuation.finish() }
}
