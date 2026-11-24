import FarportLocalization
import Foundation

/// Optional transport capability. Reading history must not send interactive input or create a shell.
public protocol TerminalHistorySession: TerminalSession {
    func captureHistory() async throws -> String
}

public enum TerminalHistorySource: String, CaseIterable, Sendable {
    case local, tmux

    public var label: String { L10n.text(self == .local ? "Farport History" : "tmux History") }
}

public enum TerminalHistoryText {
    /// A plain UTF-8 snapshot, not an ANSI recording. Keep leading/interior whitespace intact.
    public static func prepare(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result = String(normalized.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || ($0.value >= 32 && !(127...159).contains($0.value))
        })
        while result.last == "\n" { result.removeLast() }
        return result.isEmpty ? "" : result + "\n"
    }
}
