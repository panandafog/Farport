import Foundation

public enum TerminalConnectionError: LocalizedError, Sendable {
    case transport(String)
    case heartbeatTimeout
    case authentication
    case hostKeyRejected
    case serverTrust(HostKeyChallenge)
    case configuration(String)
    case localNetworkPermission
    indirect case route(stage: String, cause: TerminalConnectionError)

    public var hostKeyChallenge: HostKeyChallenge? {
        switch self {
        case .serverTrust(let challenge): challenge
        case .route(_, let cause): cause.hostKeyChallenge
        default: nil
        }
    }

    public var requiresLocalNetworkPermission: Bool {
        switch self {
        case .localNetworkPermission: true
        case .route(_, let cause): cause.requiresLocalNetworkPermission
        default: false
        }
    }

    public var allowsReconnect: Bool {
        switch self {
        case .transport, .heartbeatTimeout: true
        case .authentication, .hostKeyRejected, .serverTrust, .configuration, .localNetworkPermission: false
        case .route(_, let cause): cause.allowsReconnect
        }
    }

    public var errorDescription: String? {
        switch self {
        case .transport(let detail): "Connection lost. \(detail)"
        case .heartbeatTimeout: "The server did not respond to the connection check."
        case .authentication: "Authentication failed. Check the username, password or private key."
        case .hostKeyRejected: "The server's host key could not be verified."
        case .serverTrust(let challenge): challenge.localizedDescription
        case .configuration(let detail): detail
        case .localNetworkPermission:
            "Local Network access required. Allow Farport in Privacy & Security > Local Network, then continue."
        case .route(let stage, let cause): "\(stage): \(cause.localizedDescription)"
        }
    }
}

public struct ConnectionRecoveryPolicy: Sendable {
    public let heartbeatInterval: TimeInterval
    public let heartbeatTimeout: TimeInterval
    public let retryDelays: [TimeInterval]

    public init(heartbeatInterval: TimeInterval = 15, heartbeatTimeout: TimeInterval = 10,
                retryDelays: [TimeInterval] = [1, 2, 4, 8, 16, 30]) {
        self.heartbeatInterval = max(0.01, heartbeatInterval)
        self.heartbeatTimeout = max(0.01, heartbeatTimeout)
        self.retryDelays = retryDelays.map { max(0, $0) }
    }
}
