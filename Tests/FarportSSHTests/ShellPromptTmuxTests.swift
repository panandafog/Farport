import FarportCore
@testable import FarportSSH
import Foundation
import XCTest

final class ShellPromptTmuxTests: XCTestCase {
    func testReattachRetainsShellAndDoesNotRunNewBootstrap() throws {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("Local tmux is required for the isolated shell integration test")
        }
        try ShellPromptFixture.withDirectory { root in
            let home = root.appendingPathComponent("home"), bin = root.appendingPathComponent("bin")
            for directory in [home, bin] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let socket = root.appendingPathComponent("private.sock").path
            defer { try? control(binary, socket: socket, arguments: ["kill-server"]) }
            let wrapper = bin.appendingPathComponent("tmux")
            try ("#!/bin/sh\nexec " + ShellPromptFixture.quote(binary) + " -S " + ShellPromptFixture.quote(socket) +
                 " -f /dev/null \"$@\"\n").write(to: wrapper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
            try "printf 'FARPORT_TMUX_READY\\n'\n".write(to: home.appendingPathComponent(".bash_profile"),
                                                       atomically: true, encoding: .utf8)
            var fixture = ShellPromptFixture(root: root, home: home, shell: "/bin/bash")
            fixture.path = bin.path + ":" + fixture.path
            fixture.readyMarker = "FARPORT_TMUX_READY"
            let profile = HostProfile(terminalResumeStrategy: .tmux)
            let plan = TerminalLaunchPlan(profile: profile)
            fixture.finishMarker = "FARPORT_CAPTURE_FIRST"
            let first = try fixture.run(command: XCTUnwrap(plan.command(colors: colors(0xCC5500))),
                                         input: input("FIRST"))
            let initialDirectories = try helpers(root)
            XCTAssertEqual(initialDirectories.count, 1)
            fixture.finishMarker = "FARPORT_CAPTURE_SECOND"
            let second = try fixture.run(command: XCTUnwrap(plan.command(colors: colors(0xAABBCC))),
                                          input: input("SECOND"))
            XCTAssertEqual(try pid(first.output, tag: "FIRST"), try pid(second.output, tag: "SECOND"))
            XCTAssertTrue(second.output.contains("38;2;204;85;0"), second.output)
            XCTAssertEqual(try helpers(root), initialDirectories, "Existing tmux shells must not create another helper")
            try verifyDisabledStyles(plan, profile: profile, fixture: fixture, binary: binary, socket: socket)
        }
    }

    private func verifyDisabledStyles(_ plan: TerminalLaunchPlan, profile: HostProfile, fixture: ShellPromptFixture,
                                      binary: String, socket: String) throws {
        try control(binary, socket: socket, arguments: ["set-option", "-g", "status-style", "fg=white,bg=blue"])
        try control(binary, socket: socket, arguments: ["set-window-option", "-g", "mode-style", "fg=black,bg=yellow"])
        let disabled = TerminalDecorationColors.tinted(background: 0, accent: 0xFF8000, dark: true, useAppAccent: false)
        let command = try XCTUnwrap(plan.decorationCommand(disabled))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["PATH": fixture.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let status = try value(binary, socket: socket, arguments: ["show-options", "-qv", "-t",
                                                                  profile.tmuxSessionName, "status-style"])
        let mode = try value(binary, socket: socket, arguments: ["show-window-options", "-v", "-t",
                                                                profile.tmuxSessionName, "mode-style"])
        XCTAssertTrue(status.isEmpty, status)
        XCTAssertTrue(mode.isEmpty, mode)
        XCTAssertEqual(try value(binary, socket: socket, arguments: ["show-options", "-gv", "status-style"]),
                       "fg=white,bg=blue")
        XCTAssertEqual(try value(binary, socket: socket, arguments: ["show-window-options", "-gv", "mode-style"]),
                       "fg=black,bg=yellow")
    }

    private func value(_ binary: String, socket: String, arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-S", socket] + arguments
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func colors(_ accent: UInt32) -> TerminalDecorationColors {
        .tinted(background: 0x1E1E1E, accent: accent, dark: true, useAppAccent: true)
    }

    private func helpers(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("temporary's directory").path)
            .filter { $0.hasPrefix("farport-shell.") }.sorted()
    }

    private func input(_ tag: String) -> String {
        "printf 'FARPORT_PID_\(tag):%s\\n' \"$$\"\nprintf 'FARPORT_PS1_\(tag):%s\\n' \"$PS1\"\n" +
            "printf 'FARPORT_CAPTURE_%s\\n' \(tag)\n"
    }

    private func pid(_ output: String, tag: String) throws -> String {
        let range = try XCTUnwrap(output.range(of: "FARPORT_PID_\(tag):[0-9]+", options: .regularExpression), output)
        return String(output[range].split(separator: ":").last ?? "")
    }

    private func control(_ binary: String, socket: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-S", socket] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
