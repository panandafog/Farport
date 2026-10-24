import Citadel
import CryptoKit
import FarportCore
import Foundation
import NIO

extension CitadelFileSession: RemoteFileReplacingSession {
    func replaceContents(_ source: URL, at path: String, expected: RemoteFileRevision,
                         progress: @escaping TransferProgress) async throws {
        try await withSFTP { sftp in
            guard try await sftp.supportsAtomicRename() else { throw FinderWriteError.unsupportedReplacement }
            let permissions = try await verifyRevision(expected, at: path, sftp: sftp, progress: progress)
            let staging = path + ".harbor-\(UUID().uuidString).part"
            do {
                try await writeReplacement(source, to: staging, permissions: permissions,
                                           sftp: sftp, progress: progress)
                _ = try await verifyRevision(expected, at: path, sftp: sftp, progress: progress)
                try Task.checkCancellation()
                try await sftp.atomicRename(at: staging, to: path)
            } catch {
                try? await sftp.remove(at: staging)
                throw error
            }
        }
    }

    private func verifyRevision(_ expected: RemoteFileRevision, at path: String,
                                sftp: SFTPClient, progress: @escaping TransferProgress) async throws -> UInt32? {
        let before = try await sftp.getAttributes(at: path)
        guard before.permissions.map({ $0 & 0o170000 == 0o100000 }) == true,
              before.size == expected.size,
              before.accessModificationTime?.modificationTime == expected.modified else {
            throw FinderWriteError.conflict
        }
        let file = try await sftp.openFile(filePath: path, flags: .read)
        var hash = SHA256()
        do {
            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let buffer = try await file.read(from: offset, length: 128 * 1024)
                if buffer.readableBytes == 0 { break }
                hash.update(data: Data(buffer.readableBytesView))
                offset += UInt64(buffer.readableBytes)
                await progress(0, 0)
            }
            let after = try await file.readAttributes()
            try await file.close()
            guard after.size == before.size,
                  after.accessModificationTime?.modificationTime == before.accessModificationTime?.modificationTime,
                  Data(hash.finalize()) == expected.digest else { throw FinderWriteError.conflict }
        } catch { try? await file.close(); throw error }
        return before.permissions.map { $0 & 0o7777 }
    }

    private func writeReplacement(_ source: URL, to path: String, permissions: UInt32?, sftp: SFTPClient,
                                  progress: @escaping TransferProgress) async throws {
        let local = try FileHandle(forReadingFrom: source)
        defer { try? local.close() }
        let total = try local.seekToEnd()
        try local.seek(toOffset: 0)
        var attributes = SFTPFileAttributes()
        attributes.permissions = permissions ?? 0o600
        let file = try await sftp.openFile(filePath: path, flags: [.write, .create, .forceCreate],
                                          attributes: attributes)
        do {
            var offset: UInt64 = 0
            await progress(0, total)
            while true {
                try Task.checkCancellation()
                let data = try local.read(upToCount: 32 * 1024) ?? Data()
                if data.isEmpty { break }
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
                await progress(offset, total)
            }
            try await file.close()
        } catch { try? await file.close(); throw error }
    }
}
