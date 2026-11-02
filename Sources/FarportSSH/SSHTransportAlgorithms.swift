import Citadel
import NIO
import NIOSSH

enum SSHTransportAlgorithms {
    static var client: SSHAlgorithms {
        var algorithms = SSHAlgorithms()
        // Keep NIOSSH's preferred AES-GCM ciphers; Dropbear commonly offers only CTR/ChaCha20.
        algorithms.transportProtectionSchemes = .add([AES128CTRSHA2.self])
        return algorithms
    }
}

/// Restrict Citadel's existing AES-CTR implementation to SHA-2 MACs, without enabling its SHA-1 fallback.
final class AES128CTRSHA2: NIOSSHTransportProtection {
    static let cipherName = AES128CTR.cipherName
    static let cipherBlockSize = AES128CTR.cipherBlockSize
    static let macNames = ["hmac-sha2-256", "hmac-sha2-512"]

    private let cipher: AES128CTR
    var macBytes: Int { cipher.macBytes }

    static func keySizes(forMac mac: String?) throws -> ExpectedKeySizes {
        guard let mac, macNames.contains(mac) else { throw CitadelError.invalidMac }
        return try AES128CTR.keySizes(forMac: mac)
    }

    init(initialKeys: NIOSSHSessionKeys, mac: String?) throws {
        _ = try Self.keySizes(forMac: mac)
        cipher = try AES128CTR(initialKeys: initialKeys, mac: mac)
    }

    func updateKeys(_ newKeys: NIOSSHSessionKeys) throws {
        try cipher.updateKeys(newKeys)
    }

    func decryptFirstBlock(_ source: inout ByteBuffer) throws {
        try cipher.decryptFirstBlock(&source)
    }

    func decryptAndVerifyRemainingPacket(_ source: inout ByteBuffer, sequenceNumber: UInt32) throws -> ByteBuffer {
        try cipher.decryptAndVerifyRemainingPacket(&source, sequenceNumber: sequenceNumber)
    }

    func encryptPacket(_ packet: NIOSSHEncryptablePayload, to buffer: inout ByteBuffer, sequenceNumber: UInt32) throws {
        try cipher.encryptPacket(packet, to: &buffer, sequenceNumber: sequenceNumber)
    }
}
