import Citadel
import Crypto
import Foundation
import HarborCore
import NIO
import NIOSSH

struct SSHConnection {
    let client: SSHClient
    let parents: [SSHClient]

    func close() async {
        try? await client.close()
        for parent in parents.reversed() { try? await parent.close() }
    }
}

struct SSHRouteConnector {
    let hosts: [SavedHost]
    var timeout: TimeInterval = 15
    var localNetworkDenied: @Sendable (String, Int) async -> Bool = { host, port in
        await LocalNetworkAccess.denied(host: host, port: port)
    }
    var hostKeyVerifier: HostKeyVerifier = { endpoint, key in
        throw HostKeyChallenge(endpoint: endpoint, presented: key)
    }

    func connect(_ host: SavedHost) async throws -> SSHConnection {
        let route = try ConnectionRoute(to: host, library: hosts)
        var clients: [SSHClient] = []
        for (index, endpoint) in route.hosts.enumerated() {
            do {
                try Task.checkCancellation()
                let settings = try settings(for: endpoint)
                let client: SSHClient
                if let parent = clients.last {
                    client = try await jump(from: parent, to: settings)
                } else {
                    client = try await SSHClient.connect(to: settings)
                }
                clients.append(client)
                try Task.checkCancellation()
            } catch {
                for client in clients.reversed() { try? await client.close() }
                if Task.isCancelled { throw CancellationError() }
                let cause = await failure(error, endpoint: endpoint, direct: index == 0)
                if Task.isCancelled { throw CancellationError() }
                guard route.hosts.count > 1 else { throw cause }
                let stage = index == route.hosts.count - 1 ? "Destination" : "Jump host"
                throw TerminalConnectionError.route(
                    stage: "\(stage) '\(endpoint.profile.displayName)' (\(endpoint.profile.address))", cause: cause
                )
            }
        }
        guard let client = clients.popLast() else {
            throw TerminalConnectionError.configuration("The connection route is empty.")
        }
        return SSHConnection(client: client, parents: clients)
    }

    func failure(_ error: Error, endpoint: SavedHost, direct: Bool) async -> TerminalConnectionError {
        // Never resolve/probe a destination behind ProxyJump locally, or send SSH credentials during this check.
        if direct, TCPConnectionFailure.mayBeLocalNetworkDenied(error),
           await localNetworkDenied(endpoint.profile.hostname, endpoint.profile.port) {
            return .localNetworkPermission
        }
        return SSHFailure.connection(error) as? TerminalConnectionError ??
            .transport(error.localizedDescription)
    }

    private func jump(from parent: SSHClient, to settings: SSHClientSettings) async throws -> SSHClient {
        // Channel-open requests also need a deadline: an SSH gateway can stop responding before authentication.
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        let watchdog = Task {
            try await Task.sleep(for: .seconds(timeout))
            try Task.checkCancellation()
            try? await parent.close()
        }
        defer { watchdog.cancel() }
        do {
            return try await withTaskCancellationHandler {
                try await parent.jump(to: settings)
            } onCancel: {
                Task { try? await parent.close() }
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if ContinuousClock.now >= deadline {
                throw TerminalConnectionError.transport("Timed out opening the SSH connection through the jump host.")
            }
            if let rejection = error as? NIOSSHError, rejection.type == .channelSetupRejected {
                throw TerminalConnectionError.configuration(
                    "The jump host rejected TCP forwarding to \(settings.host):\(settings.port). " +
                    "Check forwarding permissions and destination reachability. \(rejection)"
                )
            }
            throw error
        }
    }

    private func settings(for host: SavedHost) throws -> SSHClientSettings {
        do {
            try host.validate()
            let authentication = try Self.authentication(host)
            var settings = SSHClientSettings(
                host: host.profile.hostname, port: host.profile.port,
                authenticationMethod: { authentication },
                hostKeyValidator: .custom(ServerKeyValidator(endpoint: ServerEndpoint(host.profile),
                                                             verify: hostKeyVerifier))
            )
            settings.connectTimeout = .milliseconds(Int64(timeout * 1_000))
            return settings
        } catch { throw TerminalConnectionError.configuration(error.localizedDescription) }
    }

    private static func authentication(_ host: SavedHost) throws -> SSHAuthenticationMethod {
        let username = host.profile.username
        if host.profile.authentication == .password {
            return .passwordBased(username: username, password: host.credentials.password)
        }
        let key = host.credentials.privateKey
        let passphrase = host.credentials.passphrase.isEmpty ? nil : Data(host.credentials.passphrase.utf8)
        let type = try SSHKeyDetection.detectPrivateKeyType(from: key)
        switch type {
        case .ed25519:
            return .ed25519(
                username: username,
                privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: passphrase)
            )
        case .rsa:
            return .rsa(
                username: username, privateKey: try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: passphrase)
            )
        default:
            throw HarborError.message("This MVP supports Ed25519 and RSA keys in OpenSSH format.")
        }
    }
}
