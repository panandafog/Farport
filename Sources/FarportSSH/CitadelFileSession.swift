import Citadel
import FarportCore
import Foundation
import NIO

actor CitadelFileSession: RemoteFileSession {
    let client: SSHClient
    let connection: SSHConnection
    private var closed = false
    private let chunkSize = 32 * 1024

    init(connection: SSHConnection) { self.connection = connection; client = connection.client }

    // Scope each operation to a subsystem channel; this also releases server-side directory handles.
    func withSFTP<T>(_ action: (SFTPClient) async throws -> T) async throws -> T {
        guard !closed else { throw HarborError.message("Files are disconnected.") }
        let sftp = try await client.openSFTP()
        do {
            let value = try await action(sftp)
            try? await sftp.close()
            return value
        } catch {
            try? await sftp.close()
            if let status = error as? SFTPMessage.Status {
                switch status.errorCode {
                case .noSuchFile: throw RemoteFileFailure.missing
                case .permissionDenied: throw RemoteFileFailure.permissionDenied
                case .unsupportedOperation: throw RemoteFileFailure.unsupported
                case .failure, .badMessage, .unknown: throw RemoteFileFailure.rejected
                default: break
                }
            }
            throw error
        }
    }

    func canonicalPath(_ path: String) async throws -> String {
        try await withSFTP { try await $0.getRealPath(atPath: path) }
    }

    func list(_ path: String) async throws -> [RemoteEntry] {
        try await withSFTP { sftp in
            let pages = try await sftp.listDirectory(atPath: path)
            return try pages.flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }.map { item in
                let type = (item.attributes.permissions ?? 0) & 0o170000
                let kind: RemoteEntry.Kind = type == 0o040000 ? .directory : type == 0o120000 ? .symbolicLink : .file
                return RemoteEntry(path: try RemotePath.appending(item.filename, to: path), name: item.filename,
                                   kind: kind, size: item.attributes.size,
                                   modified: item.attributes.accessModificationTime?.modificationTime)
            }.sorted {
                if ($0.kind == .directory) != ($1.kind == .directory) { return $0.kind == .directory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    func createDirectory(_ path: String) async throws {
        try await withSFTP { try await $0.createDirectory(atPath: path) }
    }

    func rename(_ path: String, to destination: String) async throws {
        try await withSFTP { try await $0.rename(at: path, to: destination) }
    }

    func remove(_ entry: RemoteEntry) async throws {
        try await withSFTP {
            if entry.kind == .directory {
                try await $0.rmdir(at: entry.path)
            } else {
                try await $0.remove(at: entry.path)
            }
        }
    }

    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) async throws {
        // Save panels grant the destination, not arbitrary siblings in its parent folder.
        let scratch = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: destination, create: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let staging = scratch.appendingPathComponent("download.part")
        guard FileManager.default.createFile(atPath: staging.path, contents: nil) else {
            throw HarborError.message("Cannot create a temporary download file.")
        }
        let local = try FileHandle(forWritingTo: staging)
        do {
            try await withSFTP { sftp in
                let file = try await sftp.openFile(filePath: path, flags: .read)
                do {
                    let total = try await file.readAttributes().size ?? 0
                    var offset: UInt64 = 0
                    await progress(0, total)
                    while true {
                        try Task.checkCancellation()
                        let buffer = try await file.read(from: offset, length: UInt32(chunkSize))
                        if buffer.readableBytes == 0 { break }
                        let data = Data(buffer.readableBytesView)
                        try local.write(contentsOf: data)
                        offset += UInt64(data.count)
                        await progress(offset, total)
                    }
                    try await file.close()
                } catch {
                    try? await file.close()
                    throw error
                }
            }
            try local.close()
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            try? local.close()
            throw error
        }
    }

    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) async throws {
        let local = try FileHandle(forReadingFrom: source)
        defer { try? local.close() }
        let total = try local.seekToEnd()
        try local.seek(toOffset: 0)
        try await withSFTP { sftp in
            // Upload to a sibling first, so a cancelled transfer never replaces an existing file.
            let staging = path + ".harbor-\(UUID().uuidString).part"
            let file = try await sftp.openFile(filePath: staging, flags: [.write, .create, .forceCreate])
            do {
                var offset: UInt64 = 0
                await progress(0, total)
                while true {
                    try Task.checkCancellation()
                    let data = try local.read(upToCount: chunkSize) ?? Data()
                    if data.isEmpty { break }
                    try await file.write(ByteBuffer(bytes: data), at: offset)
                    offset += UInt64(data.count)
                    await progress(offset, total)
                }
                try await file.close()
                try Task.checkCancellation()
                try await sftp.rename(at: staging, to: path)
            } catch {
                try? await file.close()
                try? await sftp.remove(at: staging)
                throw error
            }
        }
    }

    func close() async {
        guard !closed else { return }
        closed = true
        await connection.close()
    }
}
