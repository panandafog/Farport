import Combine
import Foundation

@MainActor
public final class TerminalPasteReview: ObservableObject {
    public struct Request: Identifiable {
        public let id = UUID()
        public let text: String
    }

    @Published public var request: Request?

    public init() {}

    public func prepare(_ text: String) -> String? {
        request = nil
        let clean = Self.sanitized(text)
        guard !clean.isEmpty else { return nil }
        if clean.contains("\n") {
            request = Request(text: clean)
            return nil
        }
        return clean
    }

    public func confirm(_ id: UUID) -> String? {
        guard let pending = request, pending.id == id else { return nil }
        request = nil
        return pending.text
    }

    public func cancel() { request = nil }

    public static func sanitized(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return String(normalized.unicodeScalars.filter {
            $0.value == 9 || $0.value == 10 || ($0.value >= 32 && !(127...159).contains($0.value))
        })
    }

    public static func bytes(_ text: String, bracketed: Bool) -> [UInt8] {
        let content = sanitized(text).replacingOccurrences(of: "\n", with: "\r")
        return Array((bracketed ? "\u{1b}[200~" + content + "\u{1b}[201~" : content).utf8)
    }
}
