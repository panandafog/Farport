@testable import Harbor
import HarborCore
import XCTest

@MainActor
final class TerminalModelTests: XCTestCase {
    func testRemoteEOFMarksDisconnectedAndKeepsHistory() async throws {
        let session = StubTerminalSession()
        let model = TerminalModel(host: SavedHost(), provider: StubProvider(sessions: [session]))
        model.connect()
        try await waitUntil { model.state == .connected }
        await session.emit("history-before-eof\r\n")
        try await waitUntil { self.history(model).contains("history-before-eof") }
        let before = history(model)
        await session.end()
        try await waitUntil { model.state == .disconnected }
        XCTAssertEqual(model.endReason, "Session ended")
        XCTAssertNotNil(model.endedAt)
        XCTAssertEqual(history(model), before)
    }

    func testTransportErrorAndReconnectPreserveHistory() async throws {
        let first = StubTerminalSession()
        let second = StubTerminalSession()
        let model = TerminalModel(host: SavedHost(), provider: StubProvider(sessions: [first, second]))
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.emit("first-session-output\r\n")
        try await waitUntil { self.history(model).contains("first-session-output") }
        await first.end(error: HarborError.message("Transport dropped"))
        try await waitUntil { model.state == .disconnected }
        XCTAssertEqual(model.endReason, "Connection lost")
        XCTAssertEqual(model.error, "Transport dropped")
        model.connect()
        try await waitUntil { model.state == .connected }
        XCTAssertNil(model.endedAt)
        XCTAssertNil(model.error)
        XCTAssertTrue(history(model).contains("first-session-output"))
        await second.emit("second-session-output\r\n")
        try await waitUntil { self.history(model).contains("second-session-output") }
        model.disconnect()
    }

    func testManualDisconnectImmediatelyDisablesInputWithoutClearingScreen() async throws {
        let session = StubTerminalSession()
        let model = TerminalModel(host: SavedHost(), provider: StubProvider(sessions: [session]))
        model.connect()
        try await waitUntil { model.state == .connected }
        await session.emit("manual-history\r\n")
        try await waitUntil { self.history(model).contains("manual-history") }
        let before = history(model)
        model.disconnect()
        XCTAssertEqual(model.state, .disconnected)
        XCTAssertEqual(model.endReason, "Disconnected by user")
        XCTAssertEqual(history(model), before)
        model.send(source: model.view, data: Array("ignored".utf8)[...])
        let sent = await session.sent
        XCTAssertTrue(sent.isEmpty)
    }

    func testWriteFailureMarksDisconnected() async throws {
        let session = StubTerminalSession(failWrites: true)
        let model = TerminalModel(host: SavedHost(), provider: StubProvider(sessions: [session]))
        model.connect()
        try await waitUntil { model.state == .connected }
        model.send(source: model.view, data: Array("command".utf8)[...])
        try await waitUntil { model.state == .disconnected }
        XCTAssertEqual(model.endReason, "Connection lost")
        XCTAssertNotNil(model.error)
    }

    func testOldCompletionCannotDisconnectReconnectedSession() async throws {
        let first = StubTerminalSession()
        let second = StubTerminalSession()
        let model = TerminalModel(host: SavedHost(), provider: StubProvider(sessions: [first, second]))
        model.connect()
        try await waitUntil { model.state == .connected }
        model.disconnect()
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.end(error: HarborError.message("Stale failure"))
        await second.emit("new-session-is-active\r\n")
        try await waitUntil { self.history(model).contains("new-session-is-active") }
        XCTAssertEqual(model.state, .connected)
        XCTAssertNil(model.error)
        XCTAssertNil(model.endedAt)
        model.disconnect()
    }

    func testPersistentModeUsesAttachAndDetachAndRetainsOutput() async throws {
        let session = StubTerminalSession()
        let host = SavedHost(profile: HostProfile(terminalResumeStrategy: .tmux))
        let model = TerminalModel(host: host, provider: StubProvider(sessions: [session]))
        XCTAssertTrue(model.usesTmux)
        XCTAssertEqual(model.connectLabel, "Attach")
        XCTAssertEqual(model.disconnectLabel, "Detach")
        XCTAssertEqual(model.sessionLabel, host.profile.tmuxSessionName)
        model.connect()
        try await waitUntil { model.state == .connected }
        await session.emit("persistent-screen\r\n")
        try await waitUntil { self.history(model).contains("persistent-screen") }
        model.disconnect()
        XCTAssertEqual(model.endReason, "Detached from tmux")
        XCTAssertEqual(model.state, .disconnected)
        XCTAssertTrue(history(model).contains("persistent-screen"))
    }

    private func history(_ model: TerminalModel) -> String {
        String(data: model.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(predicate(), "Timed out waiting for terminal state")
    }
}

private actor StubProvider: ConnectionProvider {
    var sessions: [StubTerminalSession]

    init(sessions: [StubTerminalSession]) { self.sessions = sessions }

    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        guard !sessions.isEmpty else { throw HarborError.message("No test session available") }
        return sessions.removeFirst()
    }

    func files(for host: SavedHost) async throws -> any RemoteFileSession {
        throw HarborError.message("Not used by terminal tests")
    }
}

private actor StubTerminalSession: TerminalSession {
    private let output = AsyncThrowingStream<Data, Error>.makeStream()
    private let failWrites: Bool
    private(set) var sent = Data()

    init(failWrites: Bool = false) { self.failWrites = failWrites }

    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        for try await bytes in output.stream { await onOutput(bytes) }
    }

    func send(_ data: Data) async throws {
        if failWrites { throw HarborError.message("Write failed") }
        sent.append(data)
    }

    func resize(_ size: TerminalSize) async throws {}
    func checkConnection(timeout: TimeInterval) async throws {}
    func close() async { output.continuation.finish() }
    func emit(_ text: String) { output.continuation.yield(Data(text.utf8)) }
    func end(error: Error? = nil) { output.continuation.finish(throwing: error) }
}
