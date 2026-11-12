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
            let ready = root.appendingPathComponent("startup-ready")
            try ("printf 'FARPORT_TMUX_READY\\n'\n: > " + ShellPromptFixture.quote(ready.path) + "\n")
                .write(to: home.appendingPathComponent(".bash_profile"), atomically: true, encoding: .utf8)
            var fixture = ShellPromptFixture(root: root, home: home, shell: "/bin/bash")
            fixture.path = bin.path + ":" + fixture.path
            fixture.readyPath = ready
            // Force prompt wrapping even on machines with short user/host names.
            fixture.columns = 32
            let profile = HostProfile(terminalResumeStrategy: .tmux)
            let plan = TerminalLaunchPlan(profile: profile)
            fixture.clientPIDsCommand = [binary, "-S", socket, "list-clients", "-t", profile.tmuxSessionName,
                                         "-F", "#{client_pid}"]
            let firstReport = root.appendingPathComponent("first-report")
            let secondReport = root.appendingPathComponent("second-report")
            fixture.finishPath = firstReport
            _ = try fixture.run(command: XCTUnwrap(plan.command(colors: colors(0xCC5500))),
                                input: "for farport_line in {1..40}; do " +
                                    "printf 'FARPORT_HISTORY_%s\\n' \"$farport_line\"; done\n" +
                                    input(report: firstReport))
            let initialDirectories = try helpers(root)
            XCTAssertEqual(initialDirectories.count, 1)
            try verifyStatusLabel(binary, socket: socket, profile: profile, customize: true)
            fixture.finishPath = secondReport
            let second = try fixture.run(command: XCTUnwrap(plan.command(colors: colors(0xAABBCC))),
                                          input: input(report: secondReport))
            XCTAssertFalse(second.output.contains("FARPORT_TMUX_READY"), "Startup output must be outside the pane")
            // Tmux can insert cursor/erase sequences inside printed text. Read shell state separately.
            XCTAssertEqual(try String(contentsOf: firstReport, encoding: .utf8),
                           try String(contentsOf: secondReport, encoding: .utf8))
            XCTAssertTrue(second.output.contains("38;2;204;85;0"), second.output)
            XCTAssertEqual(try helpers(root), initialDirectories, "Existing tmux shells must not create another helper")
            try verifyStatusLabel(binary, socket: socket, profile: profile, customize: false)
            try verifyDisabledStyles(plan, profile: profile, fixture: fixture, binary: binary, socket: socket)
        }
    }

    private func verifyStatusLabel(_ binary: String, socket: String, profile: HostProfile, customize: Bool) throws {
        let label = try value(binary, socket: socket,
                              arguments: ["show-options", "-v", "-t", profile.tmuxSessionName, "status-left"])
        XCTAssertEqual(label, customize ? "[Farport]" : "Custom status")
        if customize {
            try control(binary, socket: socket, arguments: ["set-option", "-t", profile.tmuxSessionName,
                                                           "status-left", "Custom status"])
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

    private func input(report: URL) -> String {
        let temporary = ShellPromptFixture.quote(report.path + ".pending")
        return "printf '%s\\n' \"$$\" \"$PS1\" > \(temporary)\n" +
            "mv \(temporary) \(ShellPromptFixture.quote(report.path))\n"
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
