#if DEBUG
import FarportCore
import Foundation

actor DemoTerminalSession: TerminalSession {
    private let host: HostProfile
    private let sessionID: UUID
    private let output = AsyncStream<Data>.makeStream()
    private var line = ""
    private var directory = "/home/alex/app"
    private var closed = false
    private var ignoreLF = false
    private var escapeState = 0
    private var accentSGR: String?

    init(host: HostProfile, sessionID: UUID) { self.host = host; self.sessionID = sessionID }

    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        guard !closed else { throw CancellationError() }
        // Deliver the complete static frame before readiness, with a steady cursor for capture stability.
        await onOutput(Data(initialScreen().utf8))
        guard !closed else { throw CancellationError() }
        await onReady()
        for await data in output.stream { try Task.checkCancellation(); await onOutput(data) }
    }

    private func initialScreen() -> String {
        var screen = "\u{1b}[2 q\u{1b}[1m" + (accentSGR ?? "\u{1b}[36m") +
            "Farport sample environment\u{1b}[0m\r\n" +
            "Ubuntu 24.04 LTS · \(host.hostname)\r\n\r\n"
        if sessionID == DemoCatalog.workspace.hosts.first?.terminals.last?.id {
            screen += "$ git status\r\n" + response(to: "git status")
        } else if sessionID == DemoCatalog.workspace.hosts.first?.terminals.dropFirst().first?.id {
            screen += "$ logs\r\n" + response(to: "logs")
        } else {
            screen += "$ docker ps\r\n" + response(to: "docker ps") +
                "\r\n$ git status\r\n" + response(to: "git status")
        }
        return screen + promptText
    }

    func send(_ data: Data) async throws {
        guard !closed else { throw CancellationError() }
        guard let text = String(data: data, encoding: .utf8) else { return }
        for scalar in text.unicodeScalars {
            if closed { break }
            if !consumeEscape(scalar) { handle(scalar) }
        }
    }

    private func consumeEscape(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 27 { escapeState = 1; return true }
        if escapeState == 1 { escapeState = scalar == "[" ? 2 : 0; return true }
        if escapeState == 2 {
            if (0x40...0x7E).contains(scalar.value) { escapeState = 0 }
            return true
        }
        return false
    }

    private func handle(_ scalar: Unicode.Scalar) {
        if scalar == "\n", ignoreLF { ignoreLF = false; return }
        ignoreLF = scalar == "\r"
        switch scalar.value {
        case 10, 13:
            emit("\r\n")
            let command = line.trimmingCharacters(in: .whitespaces)
            line = ""
            if command == "exit" { close(); return }
            emit(response(to: command))
            prompt()
        case 3: line = ""; emit("^C\r\n"); prompt()
        case 12: emit("\u{1b}[2J\u{1b}[H"); prompt()
        case 127, 8:
            if !line.isEmpty { line.removeLast(); emit("\u{8} \u{8}") }
        default:
            if scalar.value >= 32 { line.unicodeScalars.append(scalar); emit(String(scalar)) }
        }
    }

    private var promptText: String {
        (accentSGR ?? "\u{1b}[32m") + "\(host.username)@\(host.hostname)\u{1b}[0m:" +
            (accentSGR ?? "\u{1b}[34m") + "\(directory)\u{1b}[0m$ "
    }
    func setDecorationColors(_ colors: TerminalDecorationColors) {
        guard colors.useAppAccent, let accent = colors.accent else { accentSGR = nil; return }
        accentSGR = "\u{1b}[38;2;\((accent >> 16) & 255);\((accent >> 8) & 255);\(accent & 255)m"
    }
    private func prompt() { emit(promptText) }
    private func emit(_ text: String) { output.continuation.yield(Data(text.utf8)) }
    func resize(_ size: TerminalSize) async throws {}
    func checkConnection(timeout: TimeInterval) async throws { if closed { throw CancellationError() } }
    func close() { closed = true; output.continuation.finish() }

    private func response(to command: String) -> String {
        let directories = ["cd src": "/home/alex/app/src", "cd ..": "/home/alex/app",
                           "cd": "/home/alex", "cd ~": "/home/alex"]
        if let destination = directories[command] { directory = destination; return "" }
        if command == "pwd" { return directory + "\r\n" }
        if command.hasPrefix("ls") {
            return DemoScreens.listing(inSource: directory.hasSuffix("/src"), accent: accentSGR ?? "\u{1b}[34m")
        }
        return DemoScreens.responses[command] ?? "sample shell: unsupported command. Type 'help' for examples.\r\n"
    }
}
#endif
