import CryptoKit
import Foundation

public struct RemoteFileRevision: Codable, Equatable, Sendable {
    public let size: UInt64?
    public let modified: Date?
    public let digest: Data

    public init(size: UInt64?, modified: Date?, digest: Data) {
        self.size = size
        self.modified = modified
        self.digest = digest
    }
}

public protocol RemoteFileReplacingSession: RemoteFileSession {
    func replaceContents(_ source: URL, at path: String, expected: RemoteFileRevision,
                         progress: @escaping TransferProgress) async throws
}

public enum FileDigest {
    public static func sha256(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try file.read(upToCount: 128 * 1024) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return Data(digest.finalize())
    }
}

public enum FinderWriteError: Error, Sendable {
    case readOnly, conflict, unsupportedReplacement, unsupportedItem, pendingOperation
    case collision(FinderItem)
    case directoryNotEmpty

    public var message: String {
        switch self {
        case .conflict: "The server item changed. The local change has not replaced the server version."
        case .unsupportedReplacement: "The server does not support atomic SFTP replacement. The original was preserved."
        case .pendingOperation: "A previous file operation still needs to be reconciled."
        default: "The file operation could not be completed."
        }
    }
}

public enum RemoteFileFailure: Error, Sendable, LocalizedError {
    case missing, permissionDenied, unsupported, rejected

    public var errorDescription: String? {
        switch self {
        case .missing: "The remote item no longer exists."
        case .permissionDenied: "The server denied permission for this file operation."
        case .unsupported: "The server does not support this file operation."
        case .rejected: "The server rejected this file operation."
        }
    }
}
