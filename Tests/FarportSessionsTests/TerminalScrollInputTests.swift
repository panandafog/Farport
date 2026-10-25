import FarportSessions
import XCTest

final class TerminalScrollInputTests: XCTestCase {
    func testSmallTrackpadMovementsAccumulateIntoMultipleLines() {
        var input = TerminalScrollInput()
        let lines = (0..<40).reduce(0) { total, _ in total + input.lines(for: 0.25) }
        XCTAssertEqual(lines, 10)
    }

    func testDirectionChangeDoesNotConsumeMovementInTheOldDirection() {
        var input = TerminalScrollInput()
        XCTAssertEqual(input.lines(for: 0.75), 0)
        XCTAssertEqual(input.lines(for: -0.5), 0)
        XCTAssertEqual(input.lines(for: -0.5), -1)
    }

    func testNewGestureDiscardsTheOldFraction() {
        var input = TerminalScrollInput()
        XCTAssertEqual(input.lines(for: 0.75), 0)
        input.reset()
        XCTAssertEqual(input.lines(for: 0.25), 0)
    }

    func testInvalidOrLargeInputCannotProduceAnUnboundedWheelBurst() {
        var input = TerminalScrollInput()
        XCTAssertEqual(input.lines(for: .nan), 0)
        XCTAssertEqual(input.lines(for: .infinity), 0)
        XCTAssertEqual(input.lines(for: .greatestFiniteMagnitude), TerminalScrollInput.maximumSteps)
        XCTAssertEqual(input.lines(for: -.greatestFiniteMagnitude), -TerminalScrollInput.maximumSteps)
    }
}
