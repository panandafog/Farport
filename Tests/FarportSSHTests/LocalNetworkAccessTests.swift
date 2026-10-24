import FarportCore
@testable import FarportSSH
import XCTest

final class LocalNetworkAccessTests: XCTestCase {
    func testProviderWaitsOnlyOnTheFirstProxyJumpEndpoint() async {
        let first = SavedHost(profile: HostProfile(hostname: "first.gateway", port: 2222, username: "test"))
        let second = SavedHost(profile: HostProfile(hostname: "second.internal", username: "test",
                                                   jumpHostIDs: [first.id]))
        let target = SavedHost(profile: HostProfile(hostname: "never-resolve.internal", username: "test",
                                                   jumpHostIDs: [second.id]))
        var provider = SSHConnectionProvider(hosts: [first, second])
        provider.waitForNetworkAccess = { hostname, port in
            XCTAssertEqual(hostname, first.profile.hostname)
            XCTAssertEqual(port, 2222)
            return false
        }
        let available = await provider.waitForAccess(for: target)
        XCTAssertFalse(available)
    }

    func testDiagnosticReturnsDenialWithoutWaitingForAGrant() async {
        let events = AsyncStream<LocalNetworkAccess.Event>.makeStream()
        events.continuation.yield(.denied)
        let result = await LocalNetworkAccess.result(from: events.stream, waitingForAccess: false)
        events.continuation.finish()
        XCTAssertEqual(result, .denied)
    }

    func testForegroundWaitDoesNotTreatPendingPermissionAsAFinalDenial() async {
        let events = AsyncStream<LocalNetworkAccess.Event>.makeStream()
        events.continuation.yield(.denied)
        events.continuation.yield(.denied)
        events.continuation.yield(.available)
        events.continuation.finish()
        let result = await LocalNetworkAccess.result(from: events.stream, waitingForAccess: true)
        XCTAssertEqual(result, .available)
    }

    func testTimeoutOrUnavailablePathDoesNotInventAGrant() async {
        let events = AsyncStream<LocalNetworkAccess.Event>.makeStream()
        events.continuation.yield(.denied)
        events.continuation.yield(.unavailable)
        events.continuation.finish()
        let result = await LocalNetworkAccess.result(from: events.stream, waitingForAccess: true)
        XCTAssertEqual(result, .unavailable)
    }

    func testCancellationFinishesAPendingWait() async {
        let events = AsyncStream<LocalNetworkAccess.Event>.makeStream()
        let task = Task { await LocalNetworkAccess.result(from: events.stream, waitingForAccess: true) }
        events.continuation.yield(.denied)
        task.cancel()
        let result = await task.value
        events.continuation.finish()
        XCTAssertEqual(result, .unavailable)
    }

    func testAChangedFailureRequestsAFreshAttemptRatherThanKeepingAStaleDenial() async {
        let events = AsyncStream<LocalNetworkAccess.Event>.makeStream()
        events.continuation.yield(.denied)
        events.continuation.yield(.retry)
        events.continuation.finish()
        let result = await LocalNetworkAccess.result(from: events.stream, waitingForAccess: true)
        XCTAssertEqual(result, .retry)
    }

    func testAlreadyCancelledWaitNeverResolvesAHostname() async {
        let result = await withTaskGroup(of: Bool.self) { group in
            group.cancelAll()
            group.addTask { await LocalNetworkAccess.waitForAccess(host: "never-resolve.invalid", port: 22) }
            return await group.next() ?? true
        }
        XCTAssertFalse(result)
    }

    func testRealTCPReadinessAgainstTheDisposableFixture() async throws {
        guard let value = ProcessInfo.processInfo.environment["HARBOR_TEST_PORT"], let port = Int(value) else {
            throw XCTSkip("Run Scripts/ssh_fixture.py --run-tests for the loopback check")
        }
        let available = await LocalNetworkAccess.waitForAccess(host: "127.0.0.1", port: port, timeout: 1)
        XCTAssertTrue(available)
    }
}
