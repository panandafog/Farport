import Citadel
import Crypto
import FarportCore
import FarportLocalization
import Foundation

public enum SSHCredentialValidation {
    /// Cheap structural check for form validation. Decryption/authentication stays in the connection path.
    public static func validateFormat(for host: SavedHost) throws {
        if host.profile.authentication == .privateKey { _ = try keyType(host.credentials.privateKey) }
    }

    static func authentication(for host: SavedHost) throws -> SSHAuthenticationMethod {
        let username = host.profile.username
        if host.profile.authentication == .password {
            return .passwordBased(username: username, password: host.credentials.password)
        }
        let key = host.credentials.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = try keyType(key)
        let passphrase = host.credentials.passphrase.isEmpty ? nil : Data(host.credentials.passphrase.utf8)
        do {
            if type == .ed25519 {
                return .ed25519(
                    username: username,
                    privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: passphrase)
                )
            }
            return .rsa(
                username: username, privateKey: try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: passphrase)
            )
        } catch {
            throw HarborError.message(L10n.text(
                "Could not read the private key. Check the OpenSSH key file and its passphrase, then import it again."
            ))
        }
    }

    private static func keyType(_ key: String) throws -> SSHKeyType {
        let type: SSHKeyType
        do { type = try SSHKeyDetection.detectPrivateKeyType(from: key) } catch {
            throw HarborError.message(L10n.text(
                "Invalid OpenSSH private key. Import a private key file, not its .pub file or a password."
            ))
        }
        guard type == .ed25519 || type == .rsa else {
            throw HarborError.message(L10n.text("Only Ed25519 and RSA private keys in OpenSSH format are supported."))
        }
        return type
    }
}
