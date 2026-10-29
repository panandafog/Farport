import Foundation

public enum TerminalFunctionKey: String, CaseIterable, Identifiable {
    case home = "Home", end = "End", pageUp = "Page Up", pageDown = "Page Down"
    case keyF1 = "F1", keyF2 = "F2", keyF3 = "F3", keyF4 = "F4", keyF5 = "F5", keyF6 = "F6"
    case keyF7 = "F7", keyF8 = "F8", keyF9 = "F9", keyF10 = "F10", keyF11 = "F11", keyF12 = "F12"

    public var id: String { rawValue }

    public func bytes(applicationCursor: Bool, enhanced: Bool, release: Bool = false) -> [UInt8] {
        if release {
            guard enhanced else { return [] }
            guard let press = String(bytes: bytes(applicationCursor: false, enhanced: true), encoding: .utf8) else {
                return []
            }
            let body = String(press.dropFirst(2).dropLast())
            return Array("\u{1b}[\(body.isEmpty ? "1" : body);1:3\(press.suffix(1))".utf8)
        }
        if self == .keyF3, enhanced { return Array("\u{1b}[13~".utf8) }
        let prefix = applicationCursor && !enhanced ? "\u{1b}O" : "\u{1b}["
        let sequence: String
        switch self {
        case .home: sequence = prefix + "H"
        case .end: sequence = prefix + "F"
        case .pageUp: sequence = "\u{1b}[5~"
        case .pageDown: sequence = "\u{1b}[6~"
        case .keyF1, .keyF2, .keyF3, .keyF4:
            let suffix = [Self.keyF1: "P", .keyF2: "Q", .keyF3: "R", .keyF4: "S"][self] ?? "P"
            sequence = (enhanced ? "\u{1b}[1" : "\u{1b}O") + suffix
        default:
            let number = [Self.keyF5: 15, .keyF6: 17, .keyF7: 18, .keyF8: 19,
                          .keyF9: 20, .keyF10: 21, .keyF11: 23, .keyF12: 24][self] ?? 15
            sequence = "\u{1b}[\(number)~"
        }
        return Array(sequence.utf8)
    }
}
