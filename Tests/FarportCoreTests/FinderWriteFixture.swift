import FarportCore
import Foundation

struct FinderWriteFixture {
    let directory: URL
    let remote: URL
    let files: WritableTestFiles
    var catalogURL: URL { directory.appendingPathComponent("index.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        remote = directory.appendingPathComponent("remote", isDirectory: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        files = WritableTestFiles(root: remote)
    }

    func reader(writable: Bool = true) throws -> FinderRemoteReader {
        try FinderRemoteReader(rootPath: "/", catalogURL: catalogURL, writable: writable) { files }
    }

    func source(_ text: String) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        return url
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    func create(_ reader: FinderRemoteReader, name: String, text: String? = nil,
                parent: String = FinderPath.rootIdentifier, token: String = UUID().uuidString
    ) async throws -> FinderItem {
        let request = FinderCreateRequest(token: token, parentIdentifier: parent, name: name,
                                           isDirectory: text == nil, contents: try text.map(source))
        guard let item = try await reader.create(request, progress: { _, _ in }) else {
            throw HarborError.message("Test item was not created")
        }
        return item
    }
}

actor WritableTestFiles: RemoteFileReplacingSession {
    let root: URL
    var uploadCount = 0
    private var loseUploadReply = false
    private var loseRenameReply = false
    private var denyCreation = false

    init(root: URL) { self.root = root }
    func failUploadReply() { loseUploadReply = true }
    func failRenameReply() { loseRenameReply = true }
    func denyNextCreation() { denyCreation = true }
    func canonicalPath(_ path: String) -> String { path }

    func list(_ path: String) throws -> [RemoteEntry] {
        try FileManager.default.contentsOfDirectory(at: url(path), includingPropertiesForKeys: nil).map { child in
            let attributes = try FileManager.default.attributesOfItem(atPath: child.path)
            let type = attributes[.type] as? FileAttributeType
            let kind: RemoteEntry.Kind = type == .typeDirectory ? .directory :
                type == .typeSymbolicLink ? .symbolicLink : .file
            return RemoteEntry(path: try RemotePath.appending(child.lastPathComponent, to: path),
                               name: child.lastPathComponent,
                               kind: kind,
                               size: (attributes[.size] as? NSNumber)?.uint64Value,
                               modified: attributes[.modificationDate] as? Date)
        }
    }

    func createDirectory(_ path: String) throws {
        if denyCreation { denyCreation = false; throw RemoteFileFailure.permissionDenied }
        guard !FileManager.default.fileExists(atPath: url(path).path) else { throw HarborError.message("Collision") }
        try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: false)
    }

    func rename(_ path: String, to destination: String) throws {
        try FileManager.default.moveItem(at: url(path), to: url(destination))
        if loseRenameReply { loseRenameReply = false; throw HarborError.message("Lost rename reply") }
    }

    func remove(_ entry: RemoteEntry) throws { try FileManager.default.removeItem(at: url(entry.path)) }

    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) async throws {
        try Task.checkCancellation()
        try Data(contentsOf: url(path)).write(to: destination)
        await progress(1, 1)
    }

    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) async throws {
        try Task.checkCancellation()
        uploadCount += 1
        try FileManager.default.copyItem(at: source, to: url(path))
        if loseUploadReply { loseUploadReply = false; throw HarborError.message("Lost upload reply") }
        await progress(1, 1)
    }

    func replaceContents(_ source: URL, at path: String, expected: RemoteFileRevision,
                         progress: @escaping TransferProgress) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url(path).path)
        guard (attributes[.size] as? NSNumber)?.uint64Value == expected.size,
              attributes[.modificationDate] as? Date == expected.modified,
              try FileDigest.sha256(url(path)) == expected.digest else { throw FinderWriteError.conflict }
        try Data(contentsOf: source).write(to: url(path), options: .atomic)
        await progress(1, 1)
    }

    func close() { }
    private func url(_ path: String) -> URL { root.appendingPathComponent(String(path.dropFirst())) }
}
