import FarportCore
@testable import FarportSSH
import XCTest

final class TmuxIntegrationTests: XCTestCase {
    func testLaunchPlanUsesPTYExecWithOnlyGeneratedIdentifier() {
        let profile = HostProfile(name: "'; touch /tmp/unwanted; #", terminalResumeStrategy: .tmux)
        let command = TerminalLaunchPlan(profile: profile).command ?? ""
        XCTAssertTrue(command.hasPrefix("exec /bin/sh -c '"))
        XCTAssertTrue(command.contains("exec \"$tmux_binary\" -T 256,RGB new-session -A -s \(profile.tmuxSessionName)"))
        XCTAssertTrue(command.contains("set-option -t \(profile.tmuxSessionName) mouse on"))
        XCTAssertFalse(command.contains("set-option -g"))
        XCTAssertFalse(command.contains(profile.name))
        XCTAssertNil(TerminalLaunchPlan(profile: HostProfile()).command)
    }

    func testDecorationColorsApplyAtAttachAndUpdateWithoutTypingCommands() async throws {
        let host = try fixtureHost()
        let first = TerminalDecorationColors(foreground: 0x000000, background: 0xFFEAD6)
        let terminal = try await RunningTerminal.open(host, colors: first)
        do {
            try await terminal.waitFor("\u{1b}[?1049h")
            // Assert real SGR output, not just the RGB values retained by tmux options.
            try await terminal.waitFor("48;2;255;234;214")
            let query = "tmux show-options -v status-style; tmux show-window-options -v mode-style\n"
            try await terminal.session.send(Data(query.utf8))
            try await terminal.waitFor("fg=#000000,bg=#ffead6")
            let offset = await terminal.output.text.count
            await terminal.session.setDecorationColors(.init(foreground: 0xFFFFFF, background: 0x453020))
            // Query without embedding the expected colors in echoed input.
            try await terminal.session.send(Data((
                "for i in 1 2 3 4 5; do tmux show-options -v status-style; " +
                "tmux show-window-options -v mode-style; sleep 0.1; done\n"
            ).utf8))
            try await terminal.waitFor("fg=#ffffff,bg=#453020", after: offset)
            try await terminal.waitFor("48;2;69;48;32", after: offset)
            await terminal.close()
        } catch { await terminal.close(); throw error }
    }

    func testMouseWheelScrollsThroughServerHistoryAndReturnsToLiveInput() async throws {
        let host = try fixtureHost()
        let terminal = try await RunningTerminal.open(host)
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        do {
            try await terminal.waitFor("\u{1b}[?1049h")
            try await terminal.session.send(Data((
                "i=1; while [ \"$i\" -le 200 ]; do printf 'SCROLL_%s_%03d\\n' '\(token)' \"$i\"; " +
                    "i=$((i+1)); done; printf 'SCROLL_READY_%s\\n' '\(token)'\n"
            ).utf8))
            try await terminal.waitFor("SCROLL_READY_\(token)")
            let beforeScroll = await terminal.output.text.count
            try await terminal.session.send(Data(String(repeating: "\u{1b}[<64;10;10M", count: 80).utf8))
            try await terminal.waitFor("SCROLL_\(token)_001", after: beforeScroll)
            try await terminal.session.send(Data(String(repeating: "\u{1b}[<65;10;10M", count: 80).utf8))
            try await terminal.session.send(Data("printf 'SCROLL_INPUT_%s\\n' '\(token)'\n".utf8))
            try await terminal.waitFor("SCROLL_INPUT_\(token)")
            await terminal.close()
        } catch { await terminal.close(); throw error }
    }

    func testTmuxSurvivesTransportCloseAndHostReload() async throws {
        let host = try fixtureHost()
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["HARBOR_TEST_ROOT"])
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let jobFile = URL(fileURLWithPath: root).appendingPathComponent("job-\(token)")
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        let repository = JSONHostRepository(url: library.appendingPathComponent("hosts.json"))
        try repository.save([host])

        let first = try await RunningTerminal.open(host)
        do {
            try await first.waitFor("\u{1b}[?1049h")
            let setup = "export HARBOR_TOKEN=\(token); cd /; " +
                "(sleep 1; printf done > '\(jobFile.path)') </dev/null >/dev/null 2>&1 &\n" +
                "printf '\\nREADY_%s:%s\\n' \"$HARBOR_TOKEN\" \"$$\"\n"
            try await first.session.send(Data(setup.utf8))
            try await first.waitFor("READY_\(token):")
            let before = await first.output.text
            let expression = try NSRegularExpression(pattern: "READY_\(token):([0-9]+)")
            let match = try XCTUnwrap(expression.firstMatch(
                in: before, range: NSRange(before.startIndex..., in: before)
            ))
            let range = try XCTUnwrap(Range(match.range(at: 1), in: before))
            let shellPID = String(before[range])
            try await first.session.send(Data("\u{1d}harbor-fixture-abort\u{1d}".utf8))
            try await first.waitUntilEnded()
            await first.close()

            // New repository load, provider and connection model a fresh app process.
            let restored = try XCTUnwrap(repository.load().first)
            let second = try await RunningTerminal.open(restored)
            do {
                try await second.waitFor("\u{1b}[?1049h")
                try await second.session.send(Data(
                    "printf '\\nRESUMED_%s:%s:%s\\n' \"$HARBOR_TOKEN\" \"$$\" \"$PWD\"\n".utf8
                ))
                try await second.waitFor("RESUMED_\(token):\(shellPID):/")
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while !FileManager.default.fileExists(atPath: jobFile.path), ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(25))
                }
                XCTAssertEqual(try String(contentsOf: jobFile, encoding: .utf8), "done")
                await second.close()
            } catch { await second.close(); throw error }
        } catch { await first.close(); throw error }
    }

    func testControlCInterruptsForegroundProcessAndControlUClearsPendingInput() async throws {
        let terminal = try await RunningTerminal.open(fixtureHost())
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        do {
            try await terminal.waitFor("\u{1b}[?1049h")
            try await terminal.session.send(Data("printf '\\nINTERRUPT_READY_%s\\n' '\(token)'; sleep 30\n".utf8))
            try await terminal.waitFor("INTERRUPT_READY_\(token)")
            try await terminal.session.send(Data([3]))
            try await terminal.session.send(Data("printf '\\nAFTER_INTERRUPT_%s\\n' '\(token)'\n".utf8))
            try await terminal.waitFor("AFTER_INTERRUPT_\(token)")
            try await terminal.session.send(Data("printf 'BAD_EDIT_%s' '\(token)'".utf8))
            try await terminal.session.send(Data([21]))
            try await terminal.session.send(Data("printf '\\nEDIT_CLEARED_%s\\n' '\(token)'\n".utf8))
            try await terminal.waitFor("EDIT_CLEARED_\(token)")
            await terminal.close()
        } catch { await terminal.close(); throw error }
    }

    func testMissingTmuxReportsActionableError() async throws {
        var host = try fixtureHost()
        host.profile.username = "harbor-no-tmux"
        let session = try await FixtureTrust.provider().terminal(for: host)
        let ended = expectation(description: "Missing tmux fails without a fallback shell")
        let task = Task { () -> Error? in
            defer { ended.fulfill() }
            do {
                try await session.run(size: TerminalSize(), onReady: {}, onOutput: { _ in })
                return nil
            } catch { return error }
        }
        await fulfillment(of: [ended], timeout: 5)
        await session.close()
        task.cancel()
        let error = await task.value
        XCTAssertTrue(error?.localizedDescription.contains("tmux is not installed") == true)
    }

    private func fixtureHost() throws -> SavedHost {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HARBOR_TEST_TMUX"] == "1",
              let port = environment["HARBOR_TEST_PORT"].flatMap(Int.init) else {
            throw XCTSkip("Run Scripts/ssh_fixture.py --tmux --run-tests for real tmux integration tests.")
        }
        return SavedHost(
            profile: HostProfile(hostname: "127.0.0.1", port: port, username: "harbor", terminalResumeStrategy: .tmux),
            credentials: HostCredentials(password: "harbor-test")
        )
    }
}

private struct RunningTerminal {
    let session: any TerminalSession
    let output: TmuxOutput
    let task: Task<Void, Never>

    static func open(_ host: SavedHost, colors: TerminalDecorationColors? = nil) async throws -> Self {
        let session = try await FixtureTrust.provider().terminal(for: host)
        if let colors { await session.setDecorationColors(colors) }
        let output = TmuxOutput()
        let task = Task {
            do {
                try await session.run(size: TerminalSize(), onReady: {}, onOutput: { await output.append($0) })
            } catch { await output.fail(error) }
            await output.end()
        }
        return Self(session: session, output: output, task: task)
    }

    func waitFor(_ expected: String, after offset: Int = 0) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while ContinuousClock.now < deadline {
            if await output.text.dropFirst(offset).contains(expected) { return }
            if let error = await output.error { throw error }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HarborError.message("Timed out waiting for tmux output: \(expected). Received: \(await output.text)")
    }

    func close() async {
        await session.close()
        task.cancel()
        await task.value
    }

    func waitUntilEnded() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await output.ended { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HarborError.message("Terminal did not finish after the fixture aborted TCP")
    }
}

private actor TmuxOutput {
    private var bytes = Data()
    private(set) var error: Error?
    private(set) var ended = false
    var text: String { String(data: bytes, encoding: .utf8) ?? "" }
    func append(_ data: Data) { bytes.append(data) }
    func fail(_ error: Error) { self.error = error }
    func end() { ended = true }
}
