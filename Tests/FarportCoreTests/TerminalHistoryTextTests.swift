import FarportCore
import XCTest

final class TerminalHistoryTextTests: XCTestCase {
    func testUnicodeIndentationAndInteriorBlankLinesSurvivePlainTextExport() {
        let original = "  Привет 👩🏽‍💻 界\r\n\r\n\tindented  \rfinal\n\n"
        XCTAssertEqual(TerminalHistoryText.prepare(original), "  Привет 👩🏽‍💻 界\n\n\tindented  \nfinal\n")
    }

    func testEmptyBuffersAndTerminalControlCellsDoNotProduceFalseContent() {
        XCTAssertEqual(TerminalHistoryText.prepare("\r\n\n\0\u{7}\u{1b}\u{85}\u{7f}"), "")
        XCTAssertEqual(TerminalHistoryText.prepare("before\0after"), "beforeafter\n")
    }
}
