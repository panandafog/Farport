import Foundation
import XCTest

struct ShellPromptFixture {
    let root: URL
    let home: URL
    let shell: String
    var environment: [String: String] = [:]
    var path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    var readyMarker = "\u{1b}[38;2;"
    var finishMarker: String?

    func run(command: String, input: String) throws -> ShellPromptResult {
        let commandURL = root.appendingPathComponent("command.sh"), configURL = root.appendingPathComponent("pty.json")
        try command.write(to: commandURL, atomically: true, encoding: .utf8)
        let temporary = root.appendingPathComponent("temporary's directory")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        var config: [String: Any] = ["commandPath": commandURL.path, "home": home.path, "shell": shell, "path": path,
            "temporaryDirectory": temporary.path, "environment": environment, "input": input,
            "readyMarker": readyMarker]
        if let finishMarker { config["finishMarker"] = finishMarker }
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        process.arguments = ["python3", repository.appendingPathComponent("Scripts/prompt_fixture.py").path,
                             configURL.path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(data: data, encoding: .utf8) ?? "")
        return try JSONDecoder().decode(ShellPromptResult.self, from: data)
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        // Keep private tmux socket paths below Darwin's sockaddr_un limit.
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("FarportPrompt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
}

struct ShellPromptResult: Decodable {
    let output: String
    let exitCode: Int
}
