import AppKit
@testable import Farport
import FarportCore
import SwiftTerm
import XCTest

@MainActor
final class TerminalThemeTests: XCTestCase {
    func testNewDisconnectedTerminalHidesCursorAfterFontAndThemeSetup() {
        let model = TerminalModel(host: SavedHost(), provider: ThemeTestProvider())
        let recorder = ThemeOutputRecorder()
        model.view.terminalDelegate = recorder
        XCTAssertEqual(model.state, .disconnected)
        XCTAssertTrue(query("\u{1b}[?25$p", view: model.view, recorder: recorder).contains("?25;2$y"))
    }

    func testSystemColorsCursorAndSelectionHaveContrastInBothAppearances() throws {
        let view = SystemTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            try apply(name, to: view)
            XCTAssertGreaterThan(try contrast(view.nativeForegroundColor, view.nativeBackgroundColor), 7)
            XCTAssertGreaterThan(try contrast(view.nativeForegroundColor, view.selectedTextBackgroundColor), 7)
            XCTAssertEqual(view.caretColor, view.nativeForegroundColor)
            XCTAssertEqual(view.caretTextColor, view.nativeBackgroundColor)
            let background = try XCTUnwrap(view.nativeBackgroundColor.usingColorSpace(.sRGB))
            XCTAssertEqual(background.redComponent > 0.5, name == .aqua)
            for index in [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14] {
                let color = TerminalPalette(dark: name == .darkAqua).ansi[index]
                let native = NSColor(srgbRed: CGFloat(color.red) / 65_535,
                                     green: CGFloat(color.green) / 65_535,
                                     blue: CGFloat(color.blue) / 65_535, alpha: 1)
                XCTAssertGreaterThan(try contrast(native, background), 4.5, "Unreadable ANSI color \(index)")
            }
        }
    }

    func testThemeChangePreservesHistorySelectionSGRAndDimensionsWithoutSendingInput() throws {
        let view = SystemTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let recorder = ThemeOutputRecorder()
        view.terminalDelegate = recorder
        try apply(.aqua, to: view)
        view.feed(text: "\u{1b}[31mR\u{1b}[94mB\u{1b}[38;5;196mI\u{1b}[48;5;22mX\u{1b}[0m" +
                  "\u{1b}[38;2;12;34;56mT\u{1b}[48;2;65;43;21mY\u{1b}[0m\u{1b}[1;4;7mS\u{1b}[0m")
        let terminal = view.getTerminal()
        let attributes = try (0..<7).map { try XCTUnwrap(terminal.getCharData(col: $0, row: 0)).attribute }
        XCTAssertEqual(attributes[0].fg, .ansi256(code: 1))
        XCTAssertEqual(attributes[1].fg, .ansi256(code: 12))
        XCTAssertEqual(attributes[2].fg, .ansi256(code: 196))
        XCTAssertEqual(attributes[3].bg, .ansi256(code: 22))
        XCTAssertEqual(attributes[4].fg, .trueColor(red: 12, green: 34, blue: 56))
        XCTAssertEqual(attributes[5].bg, .trueColor(red: 65, green: 43, blue: 21))
        XCTAssertTrue(attributes[6].style.contains([.bold, .underline, .inverse]))
        let history = terminal.getBufferAsData()
        let dimensions = [terminal.cols, terminal.rows]
        view.selectAll()
        let selection = try XCTUnwrap(view.getSelection())
        recorder.bytes.removeAll()
        try apply(.darkAqua, to: view)
        XCTAssertTrue(recorder.bytes.isEmpty)
        XCTAssertEqual(terminal.getBufferAsData(), history)
        XCTAssertEqual(view.getSelection(), selection)
        XCTAssertEqual([terminal.cols, terminal.rows], dimensions)
        for column in 0..<7 {
            XCTAssertEqual(terminal.getCharData(col: column, row: 0)?.attribute, attributes[column])
        }
    }

    func testExtendedPaletteIsUnchangedAndDisconnectedCursorStaysHidden() throws {
        let view = SystemTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let recorder = ThemeOutputRecorder()
        view.terminalDelegate = recorder
        try apply(.aqua, to: view)
        view.getTerminal().hideCursor()
        let extended = query("\u{1b}]4;16;?;196;?;255;?\u{7}", view: view, recorder: recorder)
        XCTAssertFalse(extended.isEmpty)
        try apply(.darkAqua, to: view)
        XCTAssertEqual(query("\u{1b}]4;16;?;196;?;255;?\u{7}", view: view, recorder: recorder), extended)
        XCTAssertTrue(query("\u{1b}[?25$p", view: view, recorder: recorder).contains("?25;2$y"))
    }

    func testRepeatedAppearanceNotificationDoesNotOverwriteApplicationPalette() throws {
        let view = SystemTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let recorder = ThemeOutputRecorder()
        view.terminalDelegate = recorder
        try apply(.aqua, to: view)
        view.feed(text: "\u{1b}]4;1;rgb:11/22/33\u{7}")
        let custom = query("\u{1b}]4;1;?\u{7}", view: view, recorder: recorder)
        XCTAssertTrue(custom.contains("1111/2222/3333"))
        view.viewDidChangeEffectiveAppearance()
        XCTAssertEqual(query("\u{1b}]4;1;?\u{7}", view: view, recorder: recorder), custom)
    }

    func testWindowAppearanceChangeUpdatesAnExistingTerminal() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = SystemTerminalView(frame: window.contentLayoutRect)
        window.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        window.contentView = view
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.feed(text: "Terminal colors\r\n" +
                  "\u{1b}[31mRed  \u{1b}[32mGreen  \u{1b}[33mYellow  \u{1b}[34mBlue  " +
                  "\u{1b}[35mMagenta  \u{1b}[36mCyan\u{1b}[0m\r\n" +
                  "\u{1b}[1mBold\u{1b}[0m  \u{1b}[4mUnderline\u{1b}[0m  \u{1b}[7mInverse\u{1b}[0m\r\n" +
                  "\u{1b}[38;5;33m256 blue\u{1b}[0m  \u{1b}[38;2;180;90;150mTrue color\u{1b}[0m")
        let light = view.nativeBackgroundColor
        try verifyRendering(view, name: "Light terminal")
        window.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNotEqual(view.nativeBackgroundColor, light)
        XCTAssertLessThan(try XCTUnwrap(view.nativeBackgroundColor.usingColorSpace(.sRGB)).redComponent, 0.5)
        try verifyRendering(view, name: "Dark terminal")
    }

    private func verifyRendering(_ view: SystemTerminalView, name: String) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let attachment = XCTAttachment(image: NSImage(cgImage: image, size: view.bounds.size))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        var hues: Set<String> = []
        for row in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for column in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > color.greenComponent + 0.15 { hues.insert("red") }
                if color.greenComponent > color.redComponent + 0.15 { hues.insert("green") }
                if color.blueComponent > color.redComponent + 0.15 { hues.insert("blue") }
            }
        }
        XCTAssertEqual(hues, ["red", "green", "blue"], "\(name) must render colored text, not a blank surface")
    }

    private func apply(_ name: NSAppearance.Name, to view: SystemTerminalView) throws {
        view.appearance = try XCTUnwrap(NSAppearance(named: name))
        view.viewDidChangeEffectiveAppearance()
    }

    private func query(_ sequence: String, view: SystemTerminalView, recorder: ThemeOutputRecorder) -> String {
        recorder.bytes.removeAll()
        view.feed(text: sequence)
        return String(data: recorder.bytes, encoding: .utf8) ?? ""
    }

    private func contrast(_ first: NSColor, _ second: NSColor) throws -> CGFloat {
        func luminance(_ color: NSColor) throws -> CGFloat {
            let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            let linear = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let values = try [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}

private struct ThemeTestProvider: ConnectionProvider {
    func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        throw HarborError.message("Theme tests do not connect")
    }

    func files(for host: SavedHost) async throws -> any RemoteFileSession {
        throw HarborError.message("Theme tests do not connect")
    }
}

@MainActor
private final class ThemeOutputRecorder: @preconcurrency TerminalViewDelegate {
    var bytes = Data()

    func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
