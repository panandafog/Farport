import FarportCore
import FarportSessions
import XCTest

@MainActor
final class ConnectionRecoveryTests: XCTestCase {
    func testAutomaticallyReattachesWithoutReplayingInputAndKeepsHistory() async throws {
        let first = RecoveryTerminal()
        let second = RecoveryTerminal()
        let provider = RecoveryProvider([.success(first), .success(second)])
        let model = makeModel(provider, delays: [0.05])
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.emit("retained-history\r\n")
        try await waitUntil { self.history(model).contains("retained-history") }
        model.send(Data("before".utf8))
        try await waitUntil { await first.sent == Data("before".utf8) }
        await first.end(.transport("Lost link"))
        try await waitUntil { model.state == .reconnecting }
        model.send(Data("do-not-replay".utf8))
        try await waitUntil { await provider.attempts == 2 && model.state == .connected }
        XCTAssertTrue(history(model).contains("retained-history"))
        let replayed = await second.sent
        XCTAssertTrue(replayed.isEmpty)
        model.disconnect()
    }

    func testManualDetachCancelsPendingRetryAndWakeDoesNotRestartIt() async throws {
        let first = RecoveryTerminal()
        let provider = RecoveryProvider([.success(first)])
        let model = makeModel(provider, delays: [0.1])
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.end(.transport("Lost link"))
        try await waitUntil { model.state == .reconnecting }
        model.disconnect()
        model.suspend()
        model.resume()
        try await Task.sleep(for: .milliseconds(150))
        let attempts = await provider.attempts
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(model.state, .disconnected)
    }

    func testBrieflyOpenedConnectionsDoNotResetRetryBudget() async throws {
        let first = RecoveryTerminal()
        let provider = RecoveryProvider([
            .success(first), .success(RecoveryTerminal(startError: .transport("Immediate failure"))),
            .success(RecoveryTerminal(startError: .transport("Immediate failure")))
        ])
        let model = makeModel(provider, delays: [0.01, 0.02])
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.end(.transport("Lost link"))
        try await waitUntil { model.state == .disconnected }
        let attempts = await provider.attempts
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(model.retryAttempt, 2)
        XCTAssertEqual(model.endReason, "Reconnect attempts exhausted")
    }

    func testPermanentFailuresStopRecovery() async throws {
        for error in [TerminalConnectionError.authentication, .hostKeyRejected, .configuration("No tmux")] {
            let first = RecoveryTerminal()
            let provider = RecoveryProvider([.success(first), .failure(error)])
            let model = makeModel(provider, delays: [0.01, 0.01, 0.01])
            model.connect()
            try await waitUntil { model.state == .connected }
            await first.end(.transport("Lost link"))
            try await waitUntil { model.state == .disconnected }
            let attempts = await provider.attempts
            XCTAssertEqual(attempts, 2)
            XCTAssertEqual(model.error, error.localizedDescription)
        }
    }

    func testCleanTmuxExitDoesNotRecreateSession() async throws {
        let first = RecoveryTerminal()
        let provider = RecoveryProvider([.success(first)])
        let model = makeModel(provider, delays: [0.01])
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.end()
        try await waitUntil { model.state == .disconnected }
        try await Task.sleep(for: .milliseconds(30))
        let attempts = await provider.attempts
        XCTAssertEqual(attempts, 1)
    }

    func testHeartbeatTimeoutDetectsFailureWithoutAnyTerminalOutput() async throws {
        let first = RecoveryTerminal(probeError: .heartbeatTimeout)
        let second = RecoveryTerminal()
        let provider = RecoveryProvider([.success(first), .success(second)])
        let model = makeModel(provider, delays: [0.02], interval: 0.01)
        model.connect()
        try await waitUntil { await provider.attempts == 2 && model.state == .connected }
        let probes = await first.probes
        XCTAssertGreaterThan(probes, 0)
        model.disconnect()
    }

    func testStandardSSHHeartbeatFailureDoesNotStartAnotherShell() async throws {
        let first = RecoveryTerminal(probeError: .heartbeatTimeout)
        let provider = RecoveryProvider([.success(first)])
        let model = RecordingTerminal(host: SavedHost(), provider: provider,
                                  policy: .init(heartbeatInterval: 0.01, heartbeatTimeout: 0.01))
        model.connect()
        try await waitUntil { model.state == .disconnected }
        let attempts = await provider.attempts
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(model.error, TerminalConnectionError.heartbeatTimeout.localizedDescription)
    }

    func testWakeChecksExistingConnectionWithoutReopeningItOrSendingInput() async throws {
        let first = RecoveryTerminal(probeDelay: 0.05)
        let provider = RecoveryProvider([.success(first)])
        let model = makeModel(provider)
        model.connect()
        try await waitUntil { model.state == .connected }
        model.suspend()
        XCTAssertEqual(model.state, .suspended)
        model.send(Data("sleep-input".utf8))
        model.resume()
        XCTAssertEqual(model.state, .checking)
        model.send(Data("wake-input".utf8))
        try await waitUntil { model.state == .connected }
        let attempts = await provider.attempts
        let sent = await first.sent
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(sent.isEmpty)
        model.disconnect()
    }

    func testSleepPausesRetryAndWakeReattaches() async throws {
        let first = RecoveryTerminal()
        let provider = RecoveryProvider([.success(first), .success(RecoveryTerminal())])
        let model = makeModel(provider, delays: [0.1])
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.end(.transport("Lost link"))
        try await waitUntil { model.state == .reconnecting }
        model.suspend()
        try await Task.sleep(for: .milliseconds(150))
        let sleepingAttempts = await provider.attempts
        XCTAssertEqual(sleepingAttempts, 1)
        model.resume()
        try await waitUntil { await provider.attempts == 2 && model.state == .connected }
        model.disconnect()
    }

    private func makeModel(_ provider: RecoveryProvider, delays: [TimeInterval] = [0.01],
                           interval: TimeInterval = 5) -> RecordingTerminal {
        RecordingTerminal(host: SavedHost(profile: HostProfile(terminalResumeStrategy: .tmux)), provider: provider,
                      policy: .init(heartbeatInterval: interval, heartbeatTimeout: 0.05, retryDelays: delays))
    }

    func testBackgroundDetachesTmuxAndForegroundReattachesWithoutReplayingInput() async throws {
        let first = RecoveryTerminal()
        let second = RecoveryTerminal()
        let provider = RecoveryProvider([.success(first), .success(second)])
        let model = makeModel(provider)
        model.connect()
        try await waitUntil { model.state == .connected }
        await first.emit("before-background")
        try await waitUntil { self.history(model).contains("before-background") }
        model.suspend(disconnectTransport: true)
        XCTAssertEqual(model.state, .suspended)
        model.send(Data("ignored-background-input".utf8))
        try await Task.sleep(for: .milliseconds(30))
        let backgroundAttempts = await provider.attempts
        XCTAssertEqual(backgroundAttempts, 1)
        model.resume()
        try await waitUntil { await provider.attempts == 2 && model.state == .connected }
        let sent = await second.sent
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(history(model).contains("before-background"))
        model.disconnect()
    }

    private func history(_ model: RecordingTerminal) -> String {
        String(data: model.screen.data, encoding: .utf8) ?? ""
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let fulfilled = await predicate()
        XCTAssertTrue(fulfilled, "Timed out waiting for connection recovery")
    }
}

private actor RecoveryProvider: ConnectionProvider {
    private var results: [Result<RecoveryTerminal, TerminalConnectionError>]
    private(set) var attempts = 0

    init(_ results: [Result<RecoveryTerminal, TerminalConnectionError>]) { self.results = results }

    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        attempts += 1
        guard !results.isEmpty else { throw TerminalConnectionError.configuration("Unexpected extra attempt") }
        return try results.removeFirst().get()
    }

    func files(for host: SavedHost) async throws -> any RemoteFileSession {
        throw TerminalConnectionError.configuration("Not used by these tests")
    }
}

private actor RecoveryTerminal: TerminalSession {
    private let output = AsyncThrowingStream<Data, Error>.makeStream()
    private let startError: TerminalConnectionError?
    private let probeError: TerminalConnectionError?
    private let probeDelay: TimeInterval
    private(set) var probes = 0
    private(set) var sent = Data()

    init(startError: TerminalConnectionError? = nil, probeError: TerminalConnectionError? = nil,
         probeDelay: TimeInterval = 0) {
        self.startError = startError
        self.probeError = probeError
        self.probeDelay = probeDelay
    }

    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        if let startError { throw startError }
        for try await data in output.stream { await onOutput(data) }
    }

    func checkConnection(timeout: TimeInterval) async throws {
        probes += 1
        try await Task.sleep(for: .seconds(probeDelay))
        if let probeError { throw probeError }
    }

    func send(_ data: Data) async throws { sent.append(data) }
    func resize(_ size: TerminalSize) async throws {}
    func close() async { output.continuation.finish() }
    func emit(_ text: String) { output.continuation.yield(Data(text.utf8)) }
    func end(_ error: TerminalConnectionError? = nil) { output.continuation.finish(throwing: error) }
}
