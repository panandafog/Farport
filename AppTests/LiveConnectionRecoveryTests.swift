import Darwin
@testable import Harbor
import HarborCore
import HarborSSH
import XCTest

@MainActor
final class LiveConnectionRecoveryTests: XCTestCase {
    func testRealTmuxRecoversAutomaticallyAfterSilentPacketLoss() async throws {
        let fixture = try LiveFixture.start()
        defer { fixture.stop() }
        let model = TerminalModel(
            host: SavedHost(
                profile: HostProfile(hostname: "127.0.0.1", port: fixture.proxyPort, username: "harbor",
                                     terminalResumeStrategy: .tmux),
                credentials: HostCredentials(password: "harbor-test")
            ), provider: try fixture.provider(),
            policy: .init(heartbeatInterval: 0.05, heartbeatTimeout: 0.1, retryDelays: [0.5, 0.5])
        )
        defer { model.disconnect() }
        try await verifyRecovery(model, blackhole: fixture.blackhole)
    }

    func testTmuxRecoversThroughJumpHostAfterGatewayPacketLoss() async throws {
        let fixture = try LiveFixture.start()
        defer { fixture.stop() }
        let gateway = fixture.gateway
        let model = TerminalModel(
            host: SavedHost(
                profile: HostProfile(hostname: "build.internal", port: fixture.port, username: "harbor",
                                     terminalResumeStrategy: .tmux, jumpHostIDs: [gateway.id]),
                credentials: HostCredentials(password: "harbor-test")
            ), provider: try fixture.provider(hosts: [gateway]),
            policy: .init(heartbeatInterval: 0.05, heartbeatTimeout: 0.1, retryDelays: [0.5, 0.5])
        )
        defer { model.disconnect() }
        try await verifyRecovery(model, blackhole: fixture.jumpBlackhole)
    }

    func testIndependentTmuxTabsReattachToTheirOwnShellsAfterWorkspaceReload() async throws {
        let fixture = try LiveFixture.start()
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let hosts = JSONHostRepository(url: root.appendingPathComponent("hosts.json"))
        let tabs = JSONWorkspaceRepository(url: root.appendingPathComponent("tabs.json"))
        let gateway = fixture.gateway
        let host = SavedHost(
            profile: HostProfile(hostname: "build.internal", port: fixture.port, username: "harbor",
                                 terminalResumeStrategy: .tmux, jumpHostIDs: [gateway.id]),
            credentials: HostCredentials(password: "harbor-test")
        )
        try hosts.save([host, gateway])
        let library = LibraryModel(repository: hosts, workspaceRepository: tabs,
                                   provider: try fixture.provider(hosts: [gateway]))
        defer { library.closeAll() }
        let workspace = try XCTUnwrap(library.selectedWorkspace)
        let first = try XCTUnwrap(workspace.terminal)
        let firstPID = try await prepareShell(first, value: "FIRST")
        let secondID = workspace.addTerminal()
        let secondPID = try await prepareShell(try XCTUnwrap(workspace.terminal), value: "SECOND")
        XCTAssertNotEqual(firstPID, secondPID)
        library.closeAll()

        let restored = LibraryModel(repository: hosts, workspaceRepository: tabs,
                                    provider: try fixture.provider(hosts: [gateway]))
        defer { restored.closeAll() }
        let restoredWorkspace = try XCTUnwrap(restored.selectedWorkspace)
        XCTAssertEqual(restoredWorkspace.selectedTerminalID, secondID)
        try await verifyShell(try XCTUnwrap(restoredWorkspace.terminal), value: "SECOND", pid: secondPID)
        restoredWorkspace.selectedTerminalID = host.id
        try await verifyShell(try XCTUnwrap(restoredWorkspace.terminal), value: "FIRST", pid: firstPID)
    }

    private func prepareShell(_ model: TerminalModel, value: String) async throws -> String {
        model.connect()
        try await waitUntil { model.state == .connected && model.view.getTerminal().isCurrentBufferAlternate }
        send("export HARBOR_TAB=\(value); printf '\\nTAB_%s:%s\\n' \"$HARBOR_TAB\" \"$$\"\n", to: model)
        try await waitUntil { self.history(model).contains("TAB_\(value):") }
        let text = history(model)
        let expression = try NSRegularExpression(pattern: "TAB_\(value):([0-9]+)")
        let match = try XCTUnwrap(expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: text))
        return String(text[range])
    }

    private func verifyShell(_ model: TerminalModel, value: String, pid: String) async throws {
        XCTAssertEqual(model.state, .disconnected)
        model.connect()
        try await waitUntil { model.state == .connected && model.view.getTerminal().isCurrentBufferAlternate }
        send("printf '\\nRESTORED_%s:%s\\n' \"$HARBOR_TAB\" \"$$\"\n", to: model)
        try await waitUntil { self.history(model).contains("RESTORED_\(value):\(pid)") }
    }

    private func verifyRecovery(_ model: TerminalModel, blackhole: URL) async throws {
        model.connect()
        try await waitUntil { model.state == .connected && model.view.getTerminal().isCurrentBufferAlternate }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        send("export HARBOR_LIVE_TOKEN=\(token); printf '\\nRUN_%s:%s\\n' \"$HARBOR_LIVE_TOKEN\" \"$$\"\n", to: model)
        try await waitUntil { self.history(model).contains("RUN_\(token):") }
        let before = history(model)
        let expression = try NSRegularExpression(pattern: "RUN_\(token):([0-9]+)")
        let match = try XCTUnwrap(expression.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: before))
        let shellPID = String(before[range])
        try Data().write(to: blackhole)
        try await waitUntil { model.state == .reconnecting }
        send("this-must-not-be-replayed\n", to: model)
        try FileManager.default.removeItem(at: blackhole)
        try await waitUntil { model.state == .connected }
        send("printf '\\nBACK_%s:%s\\n' \"$HARBOR_LIVE_TOKEN\" \"$$\"\n", to: model)
        try await waitUntil { self.history(model).contains("BACK_\(token):\(shellPID)") }
        XCTAssertFalse(history(model).contains("this-must-not-be-replayed"))
        XCTAssertNil(model.error)
    }

    private func send(_ text: String, to model: TerminalModel) {
        model.send(source: model.view, data: Array(text.utf8)[...])
    }

    private func history(_ model: TerminalModel) -> String {
        String(data: model.view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard predicate() else { throw HarborError.message("Live connection recovery timed out") }
    }
}

private struct LiveFixture {
    let process: Process
    let port: Int
    let proxyPort: Int
    let blackhole: URL
    let jumpProxyPort: Int
    let jumpBlackhole: URL
    let directory: URL

    func provider(hosts: [SavedHost] = []) throws -> SSHConnectionProvider {
        SSHConnectionProvider(hosts: hosts, hostKeyVerifier: try FixtureTrust.verifier(
            directory: directory, gatewayPorts: [jumpProxyPort]
        ))
    }

    var gateway: SavedHost {
        SavedHost(profile: HostProfile(name: "Gateway", hostname: "127.0.0.1", port: jumpProxyPort, username: "jump"),
                  credentials: HostCredentials(password: "jump-test"))
    }

    private struct Description: Decodable {
        let port: Int
        let proxyPort: Int
        let blackhole: String
        let jumpProxyPort: Int
        let jumpBlackhole: String
        let directory: String
    }

    static func start() throws -> Self {
        let python = "/private/tmp/harbor-test-env/bin/python"
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw XCTSkip("Prepare the Python SSH fixture environment to run live recovery tests.")
        }
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [project.appendingPathComponent("Scripts/ssh_fixture.py").path, "--tmux"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        process.standardOutput = output
        try process.run()
        do {
            let line = output.fileHandleForReading.availableData
            guard !line.isEmpty else { throw HarborError.message("Local SSH fixture did not start") }
            let description = try JSONDecoder().decode(Description.self, from: line)
            return Self(process: process, port: description.port, proxyPort: description.proxyPort,
                        blackhole: URL(fileURLWithPath: description.blackhole),
                        jumpProxyPort: description.jumpProxyPort,
                        jumpBlackhole: URL(fileURLWithPath: description.jumpBlackhole),
                        directory: URL(fileURLWithPath: description.directory))
        } catch {
            stop(process)
            throw error
        }
    }

    func stop() {
        Self.stop(process)
    }

    private static func stop(_ process: Process) {
        if process.isRunning { process.interrupt() }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate() }
        let terminationDeadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < terminationDeadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}
