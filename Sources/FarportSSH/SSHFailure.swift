import Citadel
import FarportCore
import FarportLocalization
import NIOSSH

enum SSHFailure {
    static func connection(_ error: Error) -> Error {
        if error is CancellationError || error is TerminalConnectionError { return error }
        if error is AuthenticationFailed { return TerminalConnectionError.authentication }
        if let error = error as? SSHClientError {
            switch error {
            case .allAuthenticationOptionsFailed, .unsupportedPasswordAuthentication,
                 .unsupportedPrivateKeyAuthentication, .unsupportedHostBasedAuthentication:
                return TerminalConnectionError.authentication
            case .channelCreationFailed: break
            }
        }
        if let error = error as? NIOSSHError {
            switch error.type {
            case .invalidHostKeyForKeyExchange, .invalidExchangeHashSignature, .invalidCertificate:
                return TerminalConnectionError.hostKeyRejected
            case .keyExchangeNegotiationFailure, .unsupportedVersion, .protocolViolation, .channelSetupRejected:
                return TerminalConnectionError.configuration(
                    L10n.text("SSH negotiation failed: %@", String(describing: error))
                )
            default: break
            }
        }
        if error is SSHClient.ConnectionProbeTimedOut { return TerminalConnectionError.heartbeatTimeout }
        return TCPConnectionFailure.translate(error) ?? TerminalConnectionError.transport(error.localizedDescription)
    }
}
