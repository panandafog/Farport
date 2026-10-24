import FarportCore
import FarportLocalization
import Foundation
import NIO
import NIOSSH

struct ServerKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    let endpoint: ServerEndpoint
    let verify: HostKeyVerifier

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let components = String(openSSHPublicKey: hostKey).split(separator: " ")
        guard components.count == 2, let bytes = Data(base64Encoded: String(components[1])) else {
            validationCompletePromise.fail(TerminalConnectionError.hostKeyRejected)
            return
        }
        let key = ServerHostKey(algorithm: String(components[0]), wireData: bytes)
        // Keychain I/O must not block the SSH event loop; the handshake deadline remains in force.
        Task.detached {
            do {
                try verify(endpoint, key)
                validationCompletePromise.succeed(())
            } catch let challenge as HostKeyChallenge {
                validationCompletePromise.fail(TerminalConnectionError.serverTrust(challenge))
            } catch {
                validationCompletePromise.fail(TerminalConnectionError.configuration(
                    L10n.text("Cannot verify the server key: %@", error.localizedDescription)
                ))
            }
        }
    }
}
