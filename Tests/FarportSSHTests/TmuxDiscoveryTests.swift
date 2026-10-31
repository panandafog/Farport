import FarportCore
@testable import FarportSSH
import Foundation
import XCTest

final class TmuxDiscoveryTests: XCTestCase {
    func testFallbackFindsExecutableOutsideSSHPathAndQuotesItsPath() throws {
        try withDirectory { root in
            let missing = root.appendingPathComponent("missing")
            let notExecutable = root.appendingPathComponent("not-executable")
            try Data("not a program".utf8).write(to: notExecutable)
            let binary = try stub(in: root.appendingPathComponent("Home brew's bin"), marker: "fallback")
            let result = try run(path: root.path, candidates: [missing.path, notExecutable.path, binary.path])
            XCTAssertEqual(result.status, 0)
            XCTAssertTrue(result.output.hasPrefix("fallback\n-T\n256,RGB\nnew-session\n-A\n-s\nharbor-"))
            XCTAssertTrue(result.output.contains("\n;\nset-option\n-t\nharbor-"))
            XCTAssertTrue(result.output.hasSuffix("\nmouse\non\n"))
        }
    }

    func testAccountPathTakesPrecedenceOverFallback() throws {
        try withDirectory { root in
            let preferred = try stub(in: root.appendingPathComponent("preferred"), marker: "preferred")
            let fallback = try stub(in: root.appendingPathComponent("fallback"), marker: "fallback")
            let result = try run(path: preferred.deletingLastPathComponent().path, candidates: [fallback.path])
            XCTAssertEqual(result.status, 0)
            XCTAssertTrue(result.output.hasPrefix("preferred\n"))
        }
    }

    func testMissingTmuxExitsWithoutStartingShell() throws {
        try withDirectory { root in
            let result = try run(path: root.path, candidates: [root.appendingPathComponent("missing").path])
            XCTAssertEqual(result.status, 127)
            XCTAssertTrue(result.output.contains("tmux is unavailable"))
        }
    }

    private func stub(in directory: URL, marker: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("tmux")
        try Data("#!/bin/sh\nprintf '%s\\n' '\(marker)' \"$@\"\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        return binary
    }

    private func run(path: String, candidates: [String]) throws -> (status: Int32, output: String) {
        let profile = HostProfile(terminalResumeStrategy: .tmux)
        let command = try XCTUnwrap(TerminalLaunchPlan(profile: profile, tmuxSearchPaths: candidates).command)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["PATH": path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, try XCTUnwrap(String(data: output, encoding: .utf8)))
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
