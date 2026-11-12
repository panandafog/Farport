import FarportCore
@testable import FarportSSH
import Foundation
import XCTest

final class TmuxSessionMigrationTests: XCTestCase {
    func testLegacySessionIsRenamedWithTheSamePaneAndRunningProcess() throws {
        try withServer { server in
            let identity = TmuxSessionIdentity(id: UUID())
            try server.create(identity.legacyName)
            let before = try server.pane(identity.legacyName)
            let history = try server.history(identity.legacyName)
            XCTAssertEqual(try server.migrate(identity).status, 0)
            XCTAssertFalse(try server.exists(identity.legacyName))
            XCTAssertEqual(try server.pane(identity.name), before)
            XCTAssertEqual(try server.history(identity.name), history)
            XCTAssertEqual(try server.migrate(identity).status, 0)
            XCTAssertEqual(try server.pane(identity.name), before)
            XCTAssertEqual(try server.sessionCount(), 1)
        }
    }

    func testBothNamesKeepBothProcessesAndExposeTheRecoveredSessionName() throws {
        try withServer { server in
            let identity = TmuxSessionIdentity(id: UUID())
            try server.create(identity.legacyName)
            try server.create(identity.name)
            let legacy = try server.pane(identity.legacyName)
            let current = try server.pane(identity.name)
            let result = try server.migrate(identity)
            XCTAssertEqual(result.status, 0)
            let recovered = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(recovered.hasPrefix(identity.name + "-recovered-"))
            XCTAssertFalse(try server.exists(identity.legacyName))
            XCTAssertEqual(try server.pane(identity.name), current)
            XCTAssertEqual(try server.pane(recovered), legacy)
            XCTAssertEqual(try server.sessionCount(), 2)
            XCTAssertEqual(try server.migrate(identity).status, 0)
            XCTAssertEqual(try server.sessionCount(), 2)
        }
    }

    func testFailedRenameStopsWithoutCreatingANewSessionOrTouchingTheOldOne() throws {
        try withServer { server in
            let identity = TmuxSessionIdentity(id: UUID())
            try server.create(identity.legacyName)
            let before = try server.pane(identity.legacyName)
            let result = try server.migrate(identity, rejectRename: true)
            XCTAssertEqual(result.status, Int32(TmuxSessionMigration.failureExitCode))
            XCTAssertEqual(try server.pane(identity.legacyName), before)
            XCTAssertFalse(try server.exists(identity.name))
            XCTAssertEqual(try server.sessionCount(), 1)
        }
    }

    func testAnAbsentLegacySessionDoesNotStartAServerOrCreateAShell() throws {
        try withServer { server in
            let identity = TmuxSessionIdentity(id: UUID())
            XCTAssertEqual(try server.migrate(identity).status, 0)
            XCTAssertFalse(try server.exists(identity.name))
            XCTAssertFalse(try server.exists(identity.legacyName))
        }
    }

    func testAConcurrentCompletedRenameIsAcceptedWithoutStartingAnotherSession() throws {
        try withServer { server in
            let identity = TmuxSessionIdentity(id: UUID())
            try server.create(identity.legacyName)
            let before = try server.pane(identity.legacyName)
            let result = try server.migrate(identity, renamedByOtherClient: true)
            XCTAssertEqual(result.status, 0)
            XCTAssertEqual(try server.pane(identity.name), before)
            XCTAssertEqual(try server.sessionCount(), 1)
        }
    }

    private func withServer(_ action: (MigrationTestServer) throws -> Void) throws {
        guard let binary = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw XCTSkip("Local tmux is required for the isolated migration tests") }
        try ShellPromptFixture.withDirectory { root in
            let server = MigrationTestServer(binary: binary, root: root)
            defer { _ = try? server.control(["kill-server"]) }
            try action(server)
        }
    }
}

private struct MigrationTestServer {
    let binary: String
    let root: URL
    var socket: String { root.appendingPathComponent("migration.sock").path }

    func create(_ name: String) throws {
        let result = try control(["new-session", "-d", "-s", name,
                                  "printf 'FARPORT_MIGRATION_HISTORY\\n'; exec /bin/sleep 60"])
        XCTAssertEqual(result.status, 0, result.output)
        for _ in 0..<100 {
            if try history(name).contains("FARPORT_MIGRATION_HISTORY") { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTFail("The isolated tmux pane did not produce its initial history")
    }

    func exists(_ name: String) throws -> Bool { try control(["has-session", "-t", "=" + name]).status == 0 }

    func pane(_ name: String) throws -> String {
        let result = try control(["display-message", "-p", "-t", "=" + name + ":", "#{pane_id}:#{pane_pid}"])
        XCTAssertEqual(result.status, 0, result.output)
        return result.output
    }

    func history(_ name: String) throws -> String {
        let result = try control(["capture-pane", "-p", "-t", "=" + name + ":", "-S", "-"])
        XCTAssertEqual(result.status, 0, result.output)
        return result.output
    }

    func sessionCount() throws -> Int {
        let result = try control(["list-sessions", "-F", "#{session_id}"])
        XCTAssertEqual(result.status, 0, result.output)
        return result.output.split(separator: "\n").count
    }

    func migrate(_ identity: TmuxSessionIdentity, rejectRename: Bool = false,
                 renamedByOtherClient: Bool = false) throws -> (status: Int32, output: String) {
        let wrapper = root.appendingPathComponent("tmux-wrapper")
        let rejection = rejectRename ? "if [ \"$1\" = rename-session ]; then exit 1; fi\n" : ""
        let invocation = ShellPromptFixture.quote(binary) + " -S " + ShellPromptFixture.quote(socket) +
            " -f /dev/null \"$@\""
        let completed = renamedByOtherClient ?
            "if [ \"$1\" = rename-session ]; then " + invocation + " >/dev/null 2>&1; exit 1; fi\n" : ""
        let script = "#!/bin/sh\n" + rejection + completed + "exec " + invocation + "\n"
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let command = "tmux_binary=" + ShellPromptFixture.quote(wrapper.path) + ";\n" +
            TmuxSessionMigration.script(for: identity) + "printf '%s\\n' \"$_farport_recovered\"\n"
        return try run("/bin/sh", arguments: ["-c", command])
    }

    func control(_ arguments: [String]) throws -> (status: Int32, output: String) {
        try run(binary, arguments: ["-S", socket, "-f", "/dev/null"] + arguments)
    }

    private func run(_ executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["HOME": root.path, "PATH": "/usr/bin:/bin", "SHELL": "/bin/sh", "TERM": "xterm-256color"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
