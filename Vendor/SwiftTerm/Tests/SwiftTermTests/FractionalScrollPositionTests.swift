import XCTest
@testable import SwiftTerm

final class FractionalScrollPositionTests: XCTestCase {
    func testSubRowMovementAndReversalAreContinuous() {
        let up = FractionalScrollPosition(row: 100, fraction: 0, deltaRows: 0.2, maximumRow: 100)
        XCTAssertEqual(up.row, 99)
        XCTAssertEqual(up.fraction, 0.8, accuracy: 0.00001)
        let down = FractionalScrollPosition(row: up.row, fraction: up.fraction, deltaRows: -0.1, maximumRow: 100)
        XCTAssertEqual(down.row, 99)
        XCTAssertEqual(down.fraction, 0.9, accuracy: 0.00001)
    }

    func testEdgesConsumeOverscrollWithoutStickyRemainder() {
        for delta in [1.0, 10000] {
            let top = FractionalScrollPosition(row: 0, fraction: 0.2, deltaRows: delta, maximumRow: 100)
            XCTAssertEqual(top.row, 0)
            XCTAssertEqual(top.fraction, 0)
            let bottom = FractionalScrollPosition(row: 99, fraction: 0.8, deltaRows: -delta, maximumRow: 100)
            XCTAssertEqual(bottom.row, 100)
            XCTAssertEqual(bottom.fraction, 0)
        }
    }

    func testInvalidInputAndShrinkingHistoryStayBounded() {
        let result = FractionalScrollPosition(row: 100, fraction: .nan, deltaRows: .infinity, maximumRow: 20)
        XCTAssertEqual(result.row, 20)
        XCTAssertEqual(result.fraction, 0)
    }
}
