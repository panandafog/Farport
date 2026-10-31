import CloudKit
@testable import FarportCloud
import FarportCore
import XCTest

final class CloudSyncFailureTests: XCTestCase {
    func testCloudKitAndFoundationCancellationAreRecognizedWithoutHidingOtherFailures() {
        XCTAssertTrue(CloudSyncFailure.isCancellation(CancellationError()))
        XCTAssertTrue(CloudSyncFailure.isCancellation(CKError(.operationCancelled)))
        XCTAssertTrue(CloudSyncFailure.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(CloudSyncFailure.isCancellation(NSError(domain: NSCocoaErrorDomain,
                                                              code: NSUserCancelledError)))
        XCTAssertFalse(CloudSyncFailure.isCancellation(CKError(.serverRejectedRequest)))
        XCTAssertFalse(CloudSyncFailure.isCancellation(CKError(.networkFailure)))
    }

    func testLateCancellationCannotReplacePauseReasonOrLoseQueuedProfiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = CloudSyncFile(url: directory.appendingPathComponent("state.json"))
        var saved = CloudSyncDocument()
        saved.enabled = true
        saved.initialized = true
        let profile = HostProfile(hostname: "test.invalid", username: "test")
        try saved.ledger.bootstrap([profile])
        try file.save(saved)
        let sync = try CloudHostSync(url: file.url, containerIdentifier: "iCloud.test.invalid", changed: { _ in })
        try await sync.pause("Original server rejection")
        await sync.report(CKError(.operationCancelled))
        await sync.report(CancellationError())
        // An older operation may finish with a different failure after stopEngine as well.
        await sync.report(CKError(.networkFailure))
        let status = await sync.status
        XCTAssertEqual(status, "Original server rejection")
        let document = try file.load()
        XCTAssertFalse(document.enabled)
        XCTAssertEqual(document.pauseReason, "Original server rejection")
        XCTAssertEqual(document.ledger.profiles, [profile])
        XCTAssertEqual(document.ledger.pending, [profile.id])
    }
}
