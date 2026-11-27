import FarportCore
@testable import FarportSSH
import Foundation
import XCTest

final class SSHCommandRunnerTests: XCTestCase {
    func testExecKeepsExitCodeStderrAndUnicodeInputWithEOFThroughProxyJump() async throws {
        let fixture = try commandFixture()
        let result = try await runner(fixture).execute(.init(
            command: "cat; printf 'warning\\n' >&2; exit 17", input: "Привет\nworld\n"
        ), on: fixture.target)
        XCTAssertEqual(result.stdout, "Привет\nworld\n")
        XCTAssertEqual(result.stderr, "warning\n")
        XCTAssertEqual(result.exitCode, 17)
        XCTAssertFalse(result.succeeded)
        XCTAssertGreaterThan(result.duration, 0)
        try await fixture.waitClosed()
    }

    func testWorkingDirectoryIsQuotedAndDoesNotInjectCommands() async throws {
        let fixture = try commandFixture()
        let root = try rootDirectory()
        let name = "working ' folder ; $(touch injected)-" + UUID().uuidString
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try await runner(fixture).execute(.init(command: "pwd", directory: directory.path),
                                                     on: fixture.target)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .newlines), directory.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path))
        let failed = try await runner(fixture).execute(.init(
            command: "echo SHOULD_NOT_RUN", directory: directory.appendingPathComponent("absent").path
        ), on: fixture.target)
        XCTAssertFalse(failed.succeeded)
        XCTAssertFalse(failed.stderr.isEmpty)
        XCTAssertFalse(failed.stdout.contains("SHOULD_NOT_RUN"))
        try await fixture.waitClosed()
    }

    func testTimeoutDoesNotReplayAndClosesGateway() async throws {
        let fixture = try commandFixture()
        let marker = try rootDirectory().appendingPathComponent("command-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let request = RemoteCommandRequest(command: "echo once >> '\(marker.path)'; sleep 30", timeout: 1)
        let start = ContinuousClock.now
        do {
            _ = try await runner(fixture).execute(request, on: fixture.target)
            XCTFail("Timeout must not succeed")
        } catch RemoteCommandError.timedOut {} catch { XCTFail("Unexpected failure: \(error)") }
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "once\n")
        try await fixture.waitClosed()
    }

    func testCancellationStopsOnlyTheDedicatedRouteAndNeverRetries() async throws {
        let fixture = try commandFixture()
        let marker = try rootDirectory().appendingPathComponent("cancel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let commandRunner = try runner(fixture)
        let running = Task {
            try await commandRunner.execute(.init(command: "echo once > '\(marker.path)'; sleep 30"),
                                            on: fixture.target)
        }
        try await fixture.wait { FileManager.default.fileExists(atPath: marker.path) }
        running.cancel()
        do { _ = try await running.value; XCTFail("Cancelled command must not succeed") } catch is CancellationError {}
        try await fixture.waitClosed()
        let next = try await commandRunner.execute(.init(command: "printf healthy"), on: fixture.target)
        XCTAssertEqual(next.stdout, "healthy")
        try await fixture.waitClosed()
    }

    func testOutputLimitAndMissingExitStatusAreNotSuccessfulResults() async throws {
        let fixture = try commandFixture()
        do {
            _ = try await runner(fixture).execute(.init(
                command: "awk 'BEGIN {for(i=0;i<600000;i++) printf \"0123456789\"}'"
            ), on: fixture.target)
            XCTFail("Output must be bounded")
        } catch RemoteCommandError.outputTooLarge {} catch { XCTFail("Unexpected failure: \(error)") }
        try await fixture.waitClosed()
        do {
            _ = try await runner(fixture).execute(.init(command: "farport-fixture-missing-status"), on: fixture.target)
            XCTFail("Unconfirmed exit status must not become zero")
        } catch RemoteCommandError.completionUnknown {} catch { XCTFail("Unexpected failure: \(error)") }
        try await fixture.waitClosed()
    }

    func testUnknownServerKeyNeverExecutesACommand() async throws {
        let fixture = try commandFixture()
        let marker = try rootDirectory().appendingPathComponent("untrusted-" + UUID().uuidString)
        let blocked = SSHCommandRunner(hosts: [fixture.gateway], hostKeyVerifier: { endpoint, key in
            throw HostKeyChallenge(endpoint: endpoint, presented: key)
        })
        do {
            _ = try await blocked.execute(.init(command: "touch '\(marker.path)'"), on: fixture.target)
            XCTFail("Unknown keys must block commands")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
        try await fixture.waitClosed()
    }

    func testDeadlineAlsoCoversConnectionSetupThroughGateway() async throws {
        let fixture = try commandFixture()
        var target = fixture.target
        target.profile.hostname = "stalled.internal"
        target.profile.port = fixture.stallPort
        let start = ContinuousClock.now
        do {
            _ = try await runner(fixture).execute(.init(command: "pwd", timeout: 1), on: target)
            XCTFail("Stalled SSH handshake must time out")
        } catch RemoteCommandError.timedOut {} catch { XCTFail("Unexpected failure: \(error)") }
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
        try await fixture.waitClosed()
    }

    func testClosingCommandConnectionDoesNotDisconnectAnotherTerminal() async throws {
        let fixture = try commandFixture()
        let terminal = try await fixture.provider.terminal(for: fixture.target)
        do {
            let result = try await runner(fixture).execute(.init(command: "exit 23"), on: fixture.target)
            XCTAssertEqual(result.exitCode, 23)
            try await fixture.wait { try fixture.stats().active == 1 }
            try await terminal.checkConnection(timeout: 1)
            await terminal.close()
            try await fixture.waitClosed()
        } catch { await terminal.close(); throw error }
    }

    private func commandFixture() throws -> JumpTestFixture {
        guard ProcessInfo.processInfo.environment["HARBOR_TEST_TMUX"] == "1" else {
            throw XCTSkip("Run the disposable command/tmux fixture: Scripts/ssh_fixture.py --tmux --run-tests")
        }
        return try JumpTestFixture()
    }
    private func rootDirectory() throws -> URL {
        URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["HARBOR_TEST_ROOT"]))
    }
    private func runner(_ fixture: JumpTestFixture) throws -> SSHCommandRunner {
        SSHCommandRunner(hosts: [fixture.gateway], hostKeyVerifier: fixture.hostKeyVerifier)
    }
}
