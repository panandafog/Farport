@testable import Farport
import FarportCore
import XCTest

@MainActor
final class ConnectionOnboardingTests: XCTestCase {
    func testTerminalGuidesPermissionThenTrustAndConnectWithoutErrorBanners() async throws {
        let trust = ServerTrustModel(secrets: TestSecretStore())
        let provider = GuidedConnectionProvider(verifier: trust.verifier, needsPermission: true)
        let model = TerminalModel(host: SavedHost(), provider: provider, trust: trust)
        defer { model.disconnect() }
        model.view.feed(text: "retained-onboarding-history")
        model.connect()
        try await wait { model.requirement?.title == "Local Network Access" }
        XCTAssertNil(model.error)
        XCTAssertNil(model.endedAt)
        XCTAssertNil(trust.challenge)
        model.reviewRequirement()
        try await wait { trust.challenge != nil && trust.canContinue }
        XCTAssertEqual(model.requirement?.title, "Verify Server Identity")
        XCTAssertNil(model.error)
        XCTAssertNil(model.endedAt)
        let challenge = try XCTUnwrap(trust.challenge)
        XCTAssertNil(try trust.storedKey(challenge.endpoint))
        trust.trust(challenge, continueConnection: true)
        trust.nextChallenge()
        try await wait { model.state == .connected }
        XCTAssertNil(model.requirement)
        XCTAssertNil(model.error)
        XCTAssertEqual(try trust.storedKey(challenge.endpoint), challenge.presented)
        let attempts = await provider.attempts
        XCTAssertEqual(attempts, 3)
        let history = String(data: model.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(history.contains("retained-onboarding-history"))
    }

    func testCancellingTheTerminalInvalidatesTheTrustContinuation() async throws {
        let trust = ServerTrustModel(secrets: TestSecretStore())
        let provider = GuidedConnectionProvider(verifier: trust.verifier)
        let model = TerminalModel(host: SavedHost(), provider: provider, trust: trust)
        model.connect()
        try await wait { trust.canContinue }
        let challenge = try XCTUnwrap(trust.challenge)
        model.disconnect()
        trust.trust(challenge, continueConnection: true)
        trust.nextChallenge()
        try await Task.sleep(for: .milliseconds(20))
        let attempts = await provider.attempts
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(model.state, .disconnected)
        XCTAssertNil(model.requirement)
    }

    func testFilesTrustAndConnectContinuesOnlyTheRequestedConnection() async throws {
        let trust = ServerTrustModel(secrets: TestSecretStore())
        let provider = GuidedConnectionProvider(verifier: trust.verifier)
        let files = FilesModel(host: SavedHost(), provider: provider, trust: trust)
        defer { files.disconnect() }
        files.connect()
        try await wait { trust.canContinue }
        XCTAssertFalse(files.busy)
        XCTAssertFalse(files.connected)
        XCTAssertNil(files.error)
        trust.trust(try XCTUnwrap(trust.challenge), continueConnection: true)
        trust.nextChallenge()
        try await wait { files.connected }
        XCTAssertNil(files.requirement)
        XCTAssertEqual(files.path, "/test")
    }

    func testChangedKeyRemainsABlockingWarningAndCannotContinue() async throws {
        let trust = ServerTrustModel(secrets: TestSecretStore())
        let endpoint = GuidedConnectionProvider.endpoint
        let old = ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("old-key".utf8))
        trust.trust(HostKeyChallenge(endpoint: endpoint, presented: old))
        let provider = GuidedConnectionProvider(verifier: trust.verifier)
        let model = TerminalModel(host: SavedHost(), provider: provider, trust: trust)
        defer { model.disconnect() }
        model.connect()
        try await wait { trust.challenge != nil }
        XCTAssertTrue(model.requirement?.isWarning == true)
        XCTAssertFalse(trust.canContinue)
        trust.trust(try XCTUnwrap(trust.challenge), continueConnection: true)
        XCTAssertNotNil(trust.error)
        XCTAssertEqual(try trust.storedKey(endpoint), old)
        let attempts = await provider.attempts
        XCTAssertEqual(attempts, 1)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for connection guidance")
    }
}

private actor GuidedConnectionProvider: ConnectionProvider {
    static let endpoint = ServerEndpoint(hostname: "test.invalid", port: 22)
    private let verifier: HostKeyVerifier
    private let needsPermission: Bool
    private(set) var attempts = 0

    init(verifier: @escaping HostKeyVerifier, needsPermission: Bool = false) {
        self.verifier = verifier
        self.needsPermission = needsPermission
    }

    private func check() throws {
        attempts += 1
        if needsPermission && attempts == 1 { throw TerminalConnectionError.localNetworkPermission }
        do {
            try verifier(Self.endpoint, ServerHostKey(algorithm: "ssh-ed25519", wireData: Data("new-key".utf8)))
        } catch let challenge as HostKeyChallenge { throw TerminalConnectionError.serverTrust(challenge) }
    }

    func terminal(for host: SavedHost, sessionID: UUID) throws -> any TerminalSession {
        try check()
        return GuidedTerminal()
    }

    func files(for host: SavedHost) throws -> any RemoteFileSession {
        try check()
        return GuidedFiles()
    }
}

private actor GuidedTerminal: TerminalSession {
    private let output = AsyncThrowingStream<Data, Error>.makeStream()
    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        await onReady()
        for try await data in output.stream { await onOutput(data) }
    }
    func send(_ data: Data) {}
    func resize(_ size: TerminalSize) {}
    func checkConnection(timeout: TimeInterval) {}
    func close() { output.continuation.finish() }
}

private actor GuidedFiles: RemoteFileSession {
    func canonicalPath(_ path: String) -> String { "/test" }
    func list(_ path: String) -> [RemoteEntry] { [] }
    func createDirectory(_ path: String) {}
    func rename(_ path: String, to destination: String) {}
    func remove(_ entry: RemoteEntry) {}
    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) {}
    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) {}
    func close() {}
}
