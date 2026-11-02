import Citadel
import Crypto
import FarportCore
@testable import FarportSSH
import XCTest

final class SSHCredentialValidationTests: XCTestCase {
    func testGeneratedOpenSSHKeyCanBeValidatedAndUsedWithoutAnyConnection() throws {
        let key = Curve25519.Signing.PrivateKey().makeSSHRepresentation()
        let host = SavedHost(profile: HostProfile(hostname: "never-connect.invalid", username: "user",
                                                  authentication: .privateKey),
                             credentials: HostCredentials(privateKey: key))
        XCTAssertNoThrow(try SSHCredentialValidation.validateFormat(for: host))
        XCTAssertNoThrow(try SSHCredentialValidation.authentication(for: host))
    }

    func testMalformedAndPublicKeysShowImportGuidanceWithoutEchoingSecrets() {
        var host = SavedHost(profile: HostProfile(authentication: .privateKey))
        for key in ["a-secret-password", "ssh-ed25519 AAAA public-key", "-----BEGIN OPENSSH PRIVATE KEY-----\nbroken"] {
            host.credentials.privateKey = key
            XCTAssertThrowsError(try SSHCredentialValidation.validateFormat(for: host)) { error in
                XCTAssertTrue(error.localizedDescription.contains("private key file"))
                XCTAssertFalse(error.localizedDescription.contains(key))
                XCTAssertFalse(error.localizedDescription.contains("error 1"))
            }
        }
    }

    func testEncryptedFixtureKeyWithoutPassphraseShowsCredentialGuidance() throws {
        guard let directory = ProcessInfo.processInfo.environment["HARBOR_TEST_KEYS"] else {
            throw XCTSkip("Run with the isolated SSH fixture to check encrypted-key decoding.")
        }
        let key = try String(contentsOfFile: directory + "/ed25519-encrypted", encoding: .utf8)
        var host = SavedHost(profile: HostProfile(username: "user", authentication: .privateKey),
                             credentials: HostCredentials(privateKey: key))
        XCTAssertNoThrow(try SSHCredentialValidation.validateFormat(for: host))
        XCTAssertThrowsError(try SSHCredentialValidation.authentication(for: host)) { error in
            XCTAssertTrue(error.localizedDescription.contains("passphrase"))
            XCTAssertFalse(error.localizedDescription.contains(key))
        }
        host.credentials.passphrase = "harbor-passphrase"
        XCTAssertNoThrow(try SSHCredentialValidation.authentication(for: host))
    }
}
