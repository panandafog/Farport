import FarportSessions
import XCTest

@MainActor
final class TerminalPasteReviewTests: XCTestCase {
    func testConfirmationUsesSnapshotAndCannotBeReplayed() throws {
        let review = TerminalPasteReview()
        XCTAssertNil(review.prepare("echo first\r\necho second\n"))
        let request = try XCTUnwrap(review.request)
        XCTAssertEqual(request.text, "echo first\necho second\n")
        XCTAssertEqual(review.confirm(request.id), request.text)
        XCTAssertNil(review.confirm(request.id))
    }

    func testDisconnectOrReplacementInvalidatesConfirmation() throws {
        let review = TerminalPasteReview()
        _ = review.prepare("old\n")
        let old = try XCTUnwrap(review.request)
        review.cancel()
        XCTAssertNil(review.confirm(old.id))
        _ = review.prepare("new\n")
        XCTAssertNil(review.confirm(old.id))
        XCTAssertEqual(review.request?.text, "new\n")
    }

    func testPlainPasteAndBracketedPastePreserveUnicodeAndTabs() {
        XCTAssertEqual(TerminalPasteReview.bytes("Привет\tworld\r\n", bracketed: false),
                       Array("Привет\tworld\r".utf8))
        XCTAssertEqual(TerminalPasteReview.bytes("a\nb", bracketed: true),
                       Array("\u{1b}[200~a\rb\u{1b}[201~".utf8))
    }

    func testClipboardCannotInjectEscapeOrControlSequences() {
        XCTAssertEqual(TerminalPasteReview.sanitized("a\u{1b}[201~\u{3}\u{0}\u{9b}b"), "a[201~b")
    }

    func testSpecialKeysRespectCursorMode() {
        XCTAssertEqual(TerminalFunctionKey.keyF3.bytes(applicationCursor: false, enhanced: true, release: true),
                       Array("\u{1b}[13;1:3~".utf8))
        XCTAssertEqual(TerminalFunctionKey.keyF3.bytes(applicationCursor: false, enhanced: true),
                       Array("\u{1b}[13~".utf8))
        XCTAssertEqual(TerminalFunctionKey.home.bytes(applicationCursor: true, enhanced: false),
                       Array("\u{1b}OH".utf8))
        XCTAssertEqual(TerminalFunctionKey.home.bytes(applicationCursor: true, enhanced: true), Array("\u{1b}[H".utf8))
        XCTAssertEqual(TerminalFunctionKey.keyF12.bytes(applicationCursor: false, enhanced: false),
                       Array("\u{1b}[24~".utf8))
    }
}
