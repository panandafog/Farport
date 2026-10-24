import FarportCore
import Foundation
import XCTest

final class RemoteFileRequestTests: XCTestCase {
    func testStalledReadHasDeadlineAndClosesSession() async throws {
        let session = StalledFiles()
        do {
            _ = try await RemoteFileRequest.perform(timeout: 0.03, factory: { session }, action: {
                try await $0.list("/")
            })
            XCTFail("A stalled request must time out")
        } catch { XCTAssertEqual(error as? FinderReadError, .timedOut) }
        let closed = await session.closed
        XCTAssertTrue(closed)
    }

    func testCancellationUnblocksNetworkReadAndClosesSession() async throws {
        let session = StalledFiles()
        let task = Task {
            try await RemoteFileRequest.perform(factory: { session }, action: { try await $0.list("/") })
        }
        while !(await session.waiting) { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation succeeded as a read") } catch { }
        let closed = await session.closed
        XCTAssertTrue(closed)
    }

    func testProgressRenewsDeadlineForLongActiveTransfers() async throws {
        let session = StalledFiles()
        let activity = RemoteFileRequest.Activity()
        let result = try await RemoteFileRequest.perform(timeout: 0.2, activity: activity,
                                                        factory: { session }, action: { _ in
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(60))
                await activity.recordProgress()
            }
            return 42
        })
        XCTAssertEqual(result, 42)
        let closed = await session.closed
        XCTAssertTrue(closed)
    }
}

private actor StalledFiles: RemoteFileSession {
    var closed = false
    var waiting: Bool { pending != nil }
    private var pending: CheckedContinuation<[RemoteEntry], Error>?

    func list(_ path: String) async throws -> [RemoteEntry] {
        if closed { throw CancellationError() }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func close() {
        closed = true
        pending?.resume(throwing: CancellationError())
        pending = nil
    }

    func canonicalPath(_ path: String) -> String { path }
    func createDirectory(_ path: String) { }
    func rename(_ path: String, to destination: String) { }
    func remove(_ entry: RemoteEntry) { }
    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) { }
    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) { }
}
