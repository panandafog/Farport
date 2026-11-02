import FarportCore
@testable import FarportSSH
import Foundation
import XCTest

final class ShellPromptTests: XCTestCase {
    private let colors = TerminalDecorationColors(foreground: 0, background: 0xFFEAD6,
                                                  accent: 0xCC5500, useAppAccent: true)

    func testOptOutUsesTheOriginalShellRequestAndTmuxCommand() throws {
        let plain = TerminalLaunchPlan(profile: HostProfile())
        XCTAssertNil(plain.command)
        let disabled = TerminalDecorationColors.tinted(background: 0, accent: 0xFF8000, dark: true, useAppAccent: false)
        XCTAssertNil(try plain.command(colors: disabled))
        XCTAssertFalse(plain.requiresTmux)
        let persistent = TerminalLaunchPlan(profile: HostProfile(terminalResumeStrategy: .tmux))
        XCTAssertTrue(persistent.requiresTmux)
        let command = try XCTUnwrap(persistent.command(colors: colors))
        XCTAssertTrue(command.contains("new-session -A -s harbor-"))
        XCTAssertTrue(command.contains("farport-shell."))
        XCTAssertTrue(command.contains("status-style"))
        let reset = try XCTUnwrap(persistent.command(colors: disabled))
        XCTAssertFalse(reset.contains("farport-shell."))
        XCTAssertTrue(reset.contains("set-option -u -t"))
        XCTAssertTrue(reset.contains("set-window-option -u -t"))
    }

    func testBashLoadsProfileKeepsPromptHookAndCleansTemporaryFiles() throws {
        try ShellPromptFixture.withDirectory { root in
            let home = root.appendingPathComponent("home's directory")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let profile = home.appendingPathComponent(".bash_profile")
            let original = """
            export FARPORT_TEST_STARTUP=profile
            PROMPT_COMMAND='export FARPORT_TEST_HOOK=kept'
            PS1='old-green-prompt> '
            alias farport_alias='printf FARPORT_ALIAS_OK'
            """
            try original.write(to: profile, atomically: true, encoding: .utf8)
            let output = try run(root: root, home: home, shell: "/bin/bash")
            XCTAssertTrue(output.contains("FARPORT_STATE:profile:unset:kept"), output)
            XCTAssertTrue(output.contains("FARPORT_ALIAS_OK"), output)
            XCTAssertEqual(try String(contentsOf: profile, encoding: .utf8), original)
            try verifyCleanup(root)
        }
    }

    func testZshKeepsCustomZdotdirStartupOrderAndPromptHooks() throws {
        try ShellPromptFixture.withDirectory { root in
            let home = root.appendingPathComponent("home"), dotfiles = root.appendingPathComponent("custom's zsh")
            for path in [home, dotfiles] {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            }
            let files = [".zshenv": "export FARPORT_TEST_STARTUP=env\n",
                         ".zprofile": "FARPORT_TEST_STARTUP+=.profile\n",
                         ".zshrc": """
                         FARPORT_TEST_STARTUP+=.rc
                         _original_prompt() { export FARPORT_TEST_HOOK=kept; PROMPT='old-red> '; }
                         precmd_functions=(_original_prompt)
                         alias farport_alias='printf FARPORT_ALIAS_OK'
                         """, ".zlogin": "FARPORT_TEST_STARTUP+=.login\n"]
            for (name, text) in files { try text.write(to: dotfiles.appendingPathComponent(name),
                                                       atomically: true, encoding: .utf8) }
            let output = try run(root: root, home: home, shell: "/bin/zsh", environment: ["ZDOTDIR": dotfiles.path])
            XCTAssertTrue(output.contains("FARPORT_STATE:env.profile.rc.login:\(dotfiles.path):kept"), output)
            XCTAssertTrue(output.contains("FARPORT_ALIAS_OK"), output)
            XCTAssertTrue(FileManager.default.fileExists(atPath: dotfiles.appendingPathComponent(".zsh_history").path))
            for (name, text) in files {
                XCTAssertEqual(try String(contentsOf: dotfiles.appendingPathComponent(name), encoding: .utf8), text)
            }
            try verifyCleanup(root)
        }
    }

    func testBashArrayPromptHookWorksWithLegacySystemBash() throws {
        try ShellPromptFixture.withDirectory { root in
            let home = root.appendingPathComponent("home")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let original = """
            export FARPORT_TEST_STARTUP=array
            _original_prompt() { export FARPORT_TEST_HOOK=kept; PS1='old-green> '; }
            PROMPT_COMMAND=(_original_prompt)
            alias farport_alias='printf FARPORT_ALIAS_OK'
            """
            try original.write(to: home.appendingPathComponent(".bash_profile"), atomically: true, encoding: .utf8)
            let output = try run(root: root, home: home, shell: "/bin/bash")
            XCTAssertTrue(output.contains("FARPORT_STATE:array:unset:kept"), output)
            try verifyCleanup(root)
        }
    }

    func testUnsupportedUnixShellUsesItsLoginShellWithoutHelpers() throws {
        try ShellPromptFixture.withDirectory { root in
            let home = root.appendingPathComponent("home")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            var fixture = ShellPromptFixture(root: root, home: home, shell: "/bin/sh")
            fixture.readyMarker = "Farport:"
            let command = try XCTUnwrap(TerminalLaunchPlan(profile: HostProfile()).command(colors: colors))
            let result = try fixture.run(command: command, input: "printf 'FARPORT_FALLBACK_OK\\n'\nexit\n")
            XCTAssertEqual(result.exitCode, 0, result.output)
            XCTAssertTrue(result.output.contains("FARPORT_FALLBACK_OK"), result.output)
            XCTAssertFalse(result.output.contains("\u{1b}[38;2;"), result.output)
            try verifyCleanup(root)
        }
    }

    func testFailedStartupWriteCleansHelpersAndUsesNormalLoginShell() throws {
        try ShellPromptFixture.withDirectory { root in
            let home = root.appendingPathComponent("home"), bin = root.appendingPathComponent("bin")
            for directory in [home, bin] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let cat = bin.appendingPathComponent("cat")
            try "#!/bin/sh\nexit 1\n".write(to: cat, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cat.path)
            var fixture = ShellPromptFixture(root: root, home: home, shell: "/bin/bash")
            fixture.path = bin.path + ":" + fixture.path
            fixture.readyMarker = "Farport:"
            let command = try XCTUnwrap(TerminalLaunchPlan(profile: HostProfile()).command(colors: colors))
            let result = try fixture.run(command: command, input: "printf 'FARPORT_FALLBACK_OK\\n'\nexit\n")
            XCTAssertEqual(result.exitCode, 0, result.output)
            XCTAssertTrue(result.output.contains("FARPORT_FALLBACK_OK"), result.output)
            XCTAssertFalse(result.output.contains("\u{1b}[38;2;"), result.output)
            try verifyCleanup(root)
        }
    }

    private func run(root: URL, home: URL, shell: String, environment: [String: String] = [:]) throws -> String {
        let command = try XCTUnwrap(TerminalLaunchPlan(profile: HostProfile()).command(colors: colors))
        let input = "printf 'FARPORT_STATE:%s:%s:%s\\n' \"${FARPORT_TEST_STARTUP-}\" " +
            "\"${ZDOTDIR-unset}\" \"${FARPORT_TEST_HOOK-}\"\nfarport_alias\n" +
            "printf '\\033[32mFARPORT_GREEN\\033[0m\\n'\nexit\n"
        let fixture = ShellPromptFixture(root: root, home: home, shell: shell, environment: environment)
        let result = try fixture.run(command: command, input: input)
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("\u{1b}[38;2;204;85;0m"), result.output)
        XCTAssertTrue(result.output.contains("\u{1b}[32mFARPORT_GREEN"), result.output)
        return result.output
    }

    private func verifyCleanup(_ root: URL) throws {
        let remaining = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("temporary's directory"), includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty, "Remaining temporary items: \(remaining.map(\.lastPathComponent))")
    }

}
