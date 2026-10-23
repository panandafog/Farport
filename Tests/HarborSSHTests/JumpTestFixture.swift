import Foundation
import HarborCore
import HarborSSH
import XCTest

struct JumpTestFixture {
    let gateway: SavedHost
    let target: SavedHost
    let stallPort: Int
    let statsURL: URL
    let keyDirectory: URL
    let hostKeyVerifier: HostKeyVerifier
    var provider: SSHConnectionProvider { SSHConnectionProvider(hosts: [gateway], hostKeyVerifier: hostKeyVerifier) }

    struct Stats: Decodable {
        let active: Int
        let forwards: Int
        let shells: Int
        let destinations: [String]
    }

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let port = environment["HARBOR_TEST_PORT"].flatMap(Int.init),
              let jumpPort = environment["HARBOR_TEST_JUMP_PORT"].flatMap(Int.init),
              let stallPort = environment["HARBOR_TEST_STALL_PORT"].flatMap(Int.init),
              let stats = environment["HARBOR_TEST_JUMP_STATS"], let keys = environment["HARBOR_TEST_KEYS"] else {
            throw XCTSkip("Run Scripts/ssh_fixture.py --run-tests for ProxyJump integration tests.")
        }
        gateway = SavedHost(profile: HostProfile(name: "Gateway", hostname: "127.0.0.1", port: jumpPort,
                                                 username: "jump"),
                            credentials: HostCredentials(password: "jump-test"))
        target = SavedHost(profile: HostProfile(name: "Target", hostname: "build.internal", port: port,
                                                username: "harbor", jumpHostIDs: [gateway.id]),
                           credentials: HostCredentials(password: "harbor-test"))
        self.stallPort = stallPort
        statsURL = URL(fileURLWithPath: stats)
        keyDirectory = URL(fileURLWithPath: keys)
        hostKeyVerifier = try FixtureTrust.verifier()
    }

    func stats() throws -> Stats { try JSONDecoder().decode(Stats.self, from: Data(contentsOf: statsURL)) }
    func key(_ name: String) throws -> String {
        try String(contentsOf: keyDirectory.appendingPathComponent(name), encoding: .utf8)
    }

    func waitClosed() async throws { try await wait { try stats().active == 0 } }

    func wait(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if try await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HarborError.message("ProxyJump fixture condition timed out")
    }
}
