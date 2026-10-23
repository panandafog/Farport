import HarborCore
@testable import HarborSSH
import NIO
import XCTest

final class SSHFailureTests: XCTestCase {
    func testPOSIXPermissionDenialExplainsSettingsAndDoesNotAutoRetry() throws {
        for code in [EACCES, EPERM] {
            let failure = try XCTUnwrap(SSHFailure.connection(IOError(errnoCode: code, reason: "connect"))
                as? TerminalConnectionError)
            XCTAssertFalse(failure.allowsReconnect)
            XCTAssertTrue(failure.localizedDescription.contains("Local Network"))
            XCTAssertTrue(failure.localizedDescription.contains("errno: \(code)"))
        }
    }

    func testAggregatedConnectionRefusalKeepsTargetAndRealCause() async throws {
        let error = try await connectionFailure(ECONNREFUSED)
        let failure = try XCTUnwrap(SSHFailure.connection(error) as? TerminalConnectionError)
        XCTAssertTrue(failure.allowsReconnect)
        XCTAssertTrue(failure.localizedDescription.contains("127.0.0.1:2222"))
        XCTAssertTrue(failure.localizedDescription.contains("errno: \(ECONNREFUSED)"))
        XCTAssertFalse(failure.localizedDescription.contains("NIOPosix.NIOConnectionError error 1"))
        XCTAssertFalse(failure.localizedDescription.contains("access was denied"))
    }

    func testAggregatedPermissionDenialIsNotAMysteriousRetryableTransportFailure() async throws {
        let error = try await connectionFailure(EACCES)
        let failure = try XCTUnwrap(SSHFailure.connection(error) as? TerminalConnectionError)
        XCTAssertFalse(failure.allowsReconnect)
        XCTAssertTrue(failure.localizedDescription.contains("Local Network"))
        XCTAssertTrue(failure.localizedDescription.contains("127.0.0.1:2222"))
    }

    func testNoRouteDoesNotAssertThatTheUserDeniedPermission() async throws {
        let error = try await connectionFailure(EHOSTUNREACH)
        let failure = try XCTUnwrap(SSHFailure.connection(error) as? TerminalConnectionError)
        XCTAssertTrue(failure.allowsReconnect)
        XCTAssertTrue(failure.localizedDescription.contains("Local Network permission"))
        XCTAssertFalse(failure.localizedDescription.contains("access was denied"))
    }

    func testDNSFailureKeepsHostnameAndResolverDetails() async throws {
        let error = try await connectionFailure(nil, hostname: "unresolved.test.invalid")
        let failure = try XCTUnwrap(SSHFailure.connection(error) as? TerminalConnectionError)
        XCTAssertTrue(failure.allowsReconnect)
        XCTAssertTrue(failure.localizedDescription.contains("unresolved.test.invalid:2222"))
        XCTAssertTrue(failure.localizedDescription.contains("DNS lookup failed"))
        XCTAssertTrue(failure.localizedDescription.contains("No address records in test resolver"))
    }

    func testSystemConfirmedLocalNetworkDenialRequiresUserAction() async throws {
        let host = SavedHost(profile: HostProfile(hostname: "192.0.2.1", username: "test"))
        var connector = SSHRouteConnector(hosts: [host])
        connector.localNetworkDenied = { hostname, port in
            XCTAssertEqual(hostname, host.profile.hostname)
            XCTAssertEqual(port, 22)
            return true
        }
        let failure = await connector.failure(IOError(errnoCode: EHOSTUNREACH, reason: "connect"),
                                              endpoint: host, direct: true)
        XCTAssertFalse(failure.allowsReconnect)
        XCTAssertTrue(failure.requiresLocalNetworkPermission)
    }

    func testProxyJumpDestinationIsNeverProbedLocally() async throws {
        let host = SavedHost(profile: HostProfile(hostname: "private.internal", username: "test"))
        var connector = SSHRouteConnector(hosts: [host])
        connector.localNetworkDenied = { _, _ in
            XCTFail("A destination behind ProxyJump must never be resolved or probed locally")
            return true
        }
        let failure = await connector.failure(IOError(errnoCode: EHOSTUNREACH, reason: "connect"),
                                              endpoint: host, direct: false)
        XCTAssertTrue(failure.allowsReconnect)
    }

    func testRefusedConnectionDoesNotRunThePrivacyCheck() async throws {
        let host = SavedHost(profile: HostProfile(hostname: "127.0.0.1", username: "test"))
        var connector = SSHRouteConnector(hosts: [host])
        connector.localNetworkDenied = { _, _ in
            XCTFail("Connection refused is not a Local Network privacy failure")
            return true
        }
        let failure = await connector.failure(IOError(errnoCode: ECONNREFUSED, reason: "connect"),
                                              endpoint: host, direct: true)
        XCTAssertTrue(failure.allowsReconnect)
        XCTAssertFalse(failure.localizedDescription.contains("system denied"))
    }

    func testCancelledPrivacyCheckDoesNotStartAConnection() async {
        let result = await withTaskGroup(of: Bool.self) { group in
            group.cancelAll()
            group.addTask { await LocalNetworkAccess.denied(host: "do-not-resolve.invalid", port: 22) }
            return await group.next() ?? true
        }
        XCTAssertFalse(result)
    }

    private func connectionFailure(_ code: CInt?, hostname: String = "127.0.0.1") async throws -> NIOConnectionError {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let error: NIOConnectionError
            do {
                // Fail before TCP connect: no packet is sent, but NIO creates its real aggregate error.
                var bootstrap = ClientBootstrap(group: group)
                if let code {
                    bootstrap = bootstrap.channelInitializer { channel in
                        channel.eventLoop.makeFailedFuture(IOError(errnoCode: code, reason: "connect"))
                    }
                } else { bootstrap = bootstrap.resolver(FailingDNSResolver(eventLoop: group.next())) }
                let channel = try await bootstrap.connect(host: hostname, port: 2222).get()
                try await channel.close()
                throw HarborError.message("Expected a simulated connection failure")
            } catch let failure as NIOConnectionError { error = failure }
            try await group.shutdownGracefully()
            return error
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }
}

private struct FailingDNSResolver: Resolver, Sendable {
    let eventLoop: any EventLoop
    private struct LookupFailed: LocalizedError {
        var errorDescription: String? { "No address records in test resolver" }
    }
    func initiateAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        eventLoop.makeFailedFuture(LookupFailed())
    }
    func initiateAAAAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        eventLoop.makeFailedFuture(LookupFailed())
    }
    func cancelQueries() {}
}
