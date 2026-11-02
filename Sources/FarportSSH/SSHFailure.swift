import Citadel
import FarportCore
import FarportLocalization
import Foundation
import NIO
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
            case .channelCreationFailed: return sessionRejected
            }
        }
        if let error = error as? NIOSSHError { return protocolFailure(error.type) }
        if let error = error as? CitadelError { return citadelFailure(error) }
        if let error = error as? ChannelError { return channelFailure(error) }
        if error is SSHClient.ConnectionProbeTimedOut { return TerminalConnectionError.heartbeatTimeout }
        return TCPConnectionFailure.translate(error) ?? TerminalConnectionError.transport(
            L10n.text("SSH operation failed. %@", diagnostic(error))
        )
    }

    static func protocolFailure(_ type: NIOSSHError.ErrorType) -> TerminalConnectionError {
        switch type {
        case .invalidHostKeyForKeyExchange, .invalidExchangeHashSignature, .invalidCertificate:
            return .hostKeyRejected
        case .invalidUserAuthSignature: return .authentication
        case .tcpShutdown, .creatingChannelAfterClosure:
            return .transport(L10n.text("The server or network closed the SSH connection. Connect again."))
        default:
            return .configuration(L10n.text("%@ (SSH: %@)", protocolExplanation(type), type.description))
        }
    }

    private static func protocolExplanation(_ type: NIOSSHError.ErrorType) -> String {
        switch type {
        case .keyExchangeNegotiationFailure:
            return L10n.text(
                "No compatible SSH algorithms. The server and Farport could not agree on encryption, " +
                "key exchange or a host-key algorithm. Update the server or check its SSH configuration."
            )
        case .unsupportedVersion:
            return L10n.text("This endpoint does not support SSH 2. Check the hostname and SSH port.")
        case .channelSetupRejected:
            return sessionRejected.localizedDescription
        case .unknownPublicKey, .unknownSignature, .invalidOpenSSHPublicKey:
            return L10n.text(
                "The server used an unsupported SSH key or signature format. Check its host-key configuration."
            )
        case .weakSharedSecret, .invalidDomainParametersForKey, .invalidKeySize,
             .invalidNonceLength, .invalidMacSelected:
            return L10n.text(
                "SSH encryption could not be established safely. Check the server's cryptographic configuration."
            )
        case .invalidEncryptedPacketLength, .invalidDecryptedPlaintextLength, .insufficientPadding, .excessPadding:
            return L10n.text(
                "Encrypted SSH traffic failed validation. The connection was stopped. " +
                "Check the server and network proxy."
            )
        case .unsupportedGlobalRequest, .globalRequestRefused, .remotePeerDoesNotSupportMessage:
            return L10n.text(
                "The SSH server does not support the requested feature. Check its configuration and version."
            )
        default:
            return L10n.text(
                "The server sent an invalid or unexpected SSH message. " +
                "Check the SSH port, server logs and network proxy."
            )
        }
    }

    private static func citadelFailure(_ error: CitadelError) -> TerminalConnectionError {
        switch error {
        case .channelFailure, .channelCreationFailed: return sessionRejected
        case .unauthorized: return .authentication
        case .invalidSignature: return .hostKeyRejected
        default:
            return .configuration(L10n.text(
                "SSH encryption or session setup failed. Check the server configuration. %@", diagnostic(error)
            ))
        }
    }

    private static func channelFailure(_ error: ChannelError) -> TerminalConnectionError {
        switch error {
        case .connectTimeout:
            return .transport(L10n.text(
                "The connection timed out. Check the server address, SSH port, network and VPN."
            ))
        case .alreadyClosed, .ioOnClosedChannel, .inputClosed, .outputClosed, .eof:
            return .transport(L10n.text("The server or network closed the SSH connection. Connect again."))
        default:
            return .transport(L10n.text("SSH channel failed. %@", diagnostic(error)))
        }
    }

    private static var sessionRejected: TerminalConnectionError {
        .configuration(L10n.text(
            "The SSH server refused to open a session. Check shell/SFTP permissions and the server's session limit."
        ))
    }

    private static func diagnostic(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return String(text.prefix(1_024))
    }
}
