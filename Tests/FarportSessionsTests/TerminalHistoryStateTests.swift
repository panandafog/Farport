import FarportSessions
import XCTest

@MainActor
final class TerminalHistoryStateTests: XCTestCase {
    func testLiveOutputDoesNotShowUnreadIndicator() async {
        let history = TerminalHistoryState()
        history.update(canScroll: true, position: 1, receivedOutput: true)
        await drainUpdates()
        XCTAssertTrue(history.status.canScroll)
        XCTAssertFalse(history.status.readingHistory)
        XCTAssertFalse(history.status.hasNewOutput)
    }

    func testUnreadOutputSurvivesMoreScrollingUntilReturningToBottom() async {
        let history = TerminalHistoryState()
        history.update(canScroll: true, position: 0.5)
        await drainUpdates()
        XCTAssertTrue(history.status.readingHistory)
        XCTAssertFalse(history.status.hasNewOutput)
        history.update(canScroll: true, position: 0.5, receivedOutput: true)
        history.update(canScroll: true, position: 0.7)
        await drainUpdates()
        XCTAssertTrue(history.status.hasNewOutput)
        history.update(canScroll: true, position: 1)
        await drainUpdates()
        XCTAssertFalse(history.status.readingHistory)
        XCTAssertFalse(history.status.hasNewOutput)
    }

    func testAlternateOrClearedBufferCannotLeaveStaleHistoryControls() async {
        let history = TerminalHistoryState()
        history.update(canScroll: true, position: 0, receivedOutput: true)
        history.update(canScroll: false, position: 0)
        await drainUpdates()
        XCTAssertFalse(history.status.canScroll)
        XCTAssertFalse(history.status.readingHistory)
        XCTAssertFalse(history.status.hasNewOutput)
    }

    func testReturningToBottomWinsOverAnOutputUpdateInSameRunLoop() async {
        let history = TerminalHistoryState()
        history.update(canScroll: true, position: 0.4, receivedOutput: true)
        history.update(canScroll: true, position: 1)
        history.update(canScroll: true, position: 0.8)
        await drainUpdates()
        XCTAssertTrue(history.status.readingHistory)
        XCTAssertFalse(history.status.hasNewOutput)
    }

    func testTabsHaveIndependentHistoryStateAndPublicationIsDeferred() async {
        let first = TerminalHistoryState()
        let second = TerminalHistoryState()
        first.update(canScroll: true, position: 0, receivedOutput: true)
        XCTAssertFalse(first.status.readingHistory)
        await drainUpdates()
        XCTAssertTrue(first.status.hasNewOutput)
        XCTAssertFalse(second.status.hasNewOutput)
        XCTAssertFalse(second.status.readingHistory)
    }

    private func drainUpdates() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
