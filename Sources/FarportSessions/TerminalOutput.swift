import Foundation

/// A retained terminal renderer. Connection changes must never clear its scrollback.
@MainActor
public protocol TerminalOutput: AnyObject {
    func write(_ data: Data)
    func setCursorVisible(_ visible: Bool)
    func focus()
}
