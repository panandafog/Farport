import FarportCore
@testable import FarportSSH
import XCTest

final class ConnectionProbeTests: XCTestCase {
    func testSSHProbeTimesOutOnSilentPacketLossAndClosesTransport() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let port = environment["HARBOR_TEST_PROXY_PORT"].flatMap(Int.init),
              let path = environment["HARBOR_TEST_BLACKHOLE"] else {
            throw XCTSkip("Run the local SSH fixture for the packet-loss test.")
        }
        let control = URL(fileURLWithPath: path)
        defer { try? FileManager.default.removeItem(at: control) }
        let host = SavedHost(
            profile: HostProfile(hostname: "127.0.0.1", port: port, username: "harbor"),
            credentials: HostCredentials(password: "harbor-test")
        )
        let session = try await FixtureTrust.provider().terminal(for: host)
        do {
            try await session.checkConnection(timeout: 1)
            try Data().write(to: control)
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            do {
                try await session.checkConnection(timeout: 0.1)
                XCTFail("A silent connection must time out")
            } catch let error as TerminalConnectionError {
                guard case .heartbeatTimeout = error else { throw error }
            }
            XCTAssertLessThan(ContinuousClock.now, deadline)
            await session.close()
        } catch { await session.close(); throw error }
    }

    func testAuthenticationFailureIsPermanent() async throws {
        guard let port = ProcessInfo.processInfo.environment["HARBOR_TEST_PORT"].flatMap(Int.init) else {
            throw XCTSkip("Run the local SSH fixture for authentication tests.")
        }
        let host = SavedHost(
            profile: HostProfile(hostname: "127.0.0.1", port: port, username: "harbor"),
            credentials: HostCredentials(password: "wrong")
        )
        do {
            let session = try await FixtureTrust.provider().terminal(for: host)
            await session.close()
            XCTFail("Incorrect credentials must fail")
        } catch let error as TerminalConnectionError {
            guard case .authentication = error else { throw error }
            XCTAssertFalse(error.allowsReconnect)
        }
    }
}
