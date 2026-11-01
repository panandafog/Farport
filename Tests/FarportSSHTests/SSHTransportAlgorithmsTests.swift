import Citadel
import FarportCore
@testable import FarportSSH
import XCTest

final class SSHTransportAlgorithmsTests: XCTestCase {
    func testCTRRejectsSHA1AndAbsentMAC() throws {
        for mac in [nil, "hmac-sha1", "none"] as [String?] {
            XCTAssertThrowsError(try AES128CTRSHA2.keySizes(forMac: mac))
        }
        for mac in ["hmac-sha2-256", "hmac-sha2-512"] {
            XCTAssertNoThrow(try AES128CTRSHA2.keySizes(forMac: mac))
        }
    }

    func testCompatibilityOnlyAddsCTRAndPreservesDefaultKeyExchangeAndHostKeys() {
        let algorithms = SSHTransportAlgorithms.client
        guard case .add(let ciphers) = algorithms.transportProtectionSchemes else {
            return XCTFail("Keep AES-GCM as the preferred default; add CTR as a fallback")
        }
        XCTAssertEqual(ciphers.map { $0.cipherName }, ["aes128-ctr"])
        XCTAssertEqual(ciphers.flatMap { $0.macNames }, ["hmac-sha2-256", "hmac-sha2-512"])
        XCTAssertNil(algorithms.keyExchangeAlgorithms)
        XCTAssertNil(algorithms.publicKeyAlgorihtms)
    }

    func testRouterAlgorithmsSupportBidirectionalTerminalAndSFTP() async throws {
        let host = try routerHost()
        let provider = try FixtureTrust.provider()
        let terminal = try await provider.terminal(for: host)
        let received = expectation(description: "AES-CTR terminal output reaches the client")
        let output = RouterOutput()
        let task = Task {
            try await terminal.run(size: TerminalSize(), onReady: {
                try? await terminal.send(Data("echo router-ctr-ok\nexit\n".utf8))
            }, onOutput: { data in
                if await output.append(data) { received.fulfill() }
            })
        }
        await fulfillment(of: [received], timeout: 10)
        await terminal.close()
        task.cancel()
        _ = await task.result

        let files = try await provider.files(for: host)
        do {
            let entries = try await files.list("/")
            XCTAssertTrue(entries.contains { $0.name == "hello.txt" })
            await files.close()
        } catch { await files.close(); throw error }
    }

    func testRouterStillRequiresExplicitHostTrust() async throws {
        let host = try routerHost()
        do {
            let files = try await SSHConnectionProvider().files(for: host)
            await files.close()
            XCTFail("CTR negotiation must not bypass host-key verification")
        } catch let error as TerminalConnectionError {
            XCTAssertNotNil(error.hostKeyChallenge)
            XCTAssertFalse(error.allowsReconnect)
        }
    }

    private func routerHost() throws -> SavedHost {
        guard let port = ProcessInfo.processInfo.environment["HARBOR_TEST_CTR_PORT"].flatMap(Int.init) else {
            throw XCTSkip("Start the isolated SSH fixture for its Dropbear-compatible listener.")
        }
        return SavedHost(profile: HostProfile(hostname: "127.0.0.1", port: port, username: "harbor"),
                         credentials: HostCredentials(password: "harbor-test"))
    }
}

private actor RouterOutput {
    private var buffer = Data()
    private var fulfilled = false

    func append(_ data: Data) -> Bool {
        buffer.append(data)
        guard !fulfilled, let text = String(data: buffer, encoding: .utf8), text.contains("router-ctr-ok") else {
            return false
        }
        fulfilled = true
        return true
    }
}
