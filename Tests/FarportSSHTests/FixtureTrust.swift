import FarportCore
import FarportSSH
import Foundation
import XCTest

enum FixtureTrust {
    static func verifier() throws -> HostKeyVerifier {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["HARBOR_TEST_KEYS"],
              let port = environment["HARBOR_TEST_JUMP_PORT"].flatMap(Int.init) else {
            throw XCTSkip("Start the disposable SSH fixture to load its out-of-band server pins.")
        }
        return try verifier(directory: URL(fileURLWithPath: directory), gatewayPorts: [port])
    }

    static func provider(hosts: [SavedHost] = []) throws -> SSHConnectionProvider {
        SSHConnectionProvider(hosts: hosts, hostKeyVerifier: try verifier())
    }

    static func verifier(directory: URL, gatewayPorts: Set<Int>) throws -> HostKeyVerifier {
        let server = try key(directory.appendingPathComponent("server-host.pub"))
        let gateway = try key(directory.appendingPathComponent("gateway-host.pub"))
        return { endpoint, presented in
            let expected = gatewayPorts.contains(endpoint.port) || endpoint.hostname == "gateway.internal" ?
                gateway : server
            guard presented == expected else {
                throw HostKeyChallenge(endpoint: endpoint, presented: presented, trusted: expected)
            }
        }
    }

    static func key(_ url: URL) throws -> ServerHostKey {
        let parts = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2, let data = Data(base64Encoded: String(parts[1])) else {
            throw HarborError.message("Invalid fixture host public key")
        }
        return ServerHostKey(algorithm: String(parts[0]), wireData: data)
    }
}
