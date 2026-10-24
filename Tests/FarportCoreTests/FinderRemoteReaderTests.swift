import FarportCore
import Foundation
import XCTest

final class FinderRemoteReaderTests: XCTestCase {
    func testReadOnlyBinaryDownloadAndStableIndexAcrossRestart() async throws {
        let fixture = try FinderReaderFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let anchor = await reader.currentAnchor()
        let items = try await reader.list(FinderPath.rootIdentifier)
        XCTAssertEqual(items.map(\.name), ["folder", "hello.bin"])
        let item = try XCTUnwrap(items.first { $0.name == "hello.bin" })
        let url = fixture.directory.appendingPathComponent("download.bin")
        _ = try await reader.download(item.identifier, version: item.contentVersion, to: url) { _, _ in }
        XCTAssertEqual(try Data(contentsOf: url), fixture.bytes)
        let restarted = try fixture.reader()
        let changes = try await restarted.changes(since: anchor, container: nil)
        XCTAssertEqual(changes.updated.map(\.identifier), items.map(\.identifier))
        let writes = await fixture.session.writes
        let opens = await fixture.session.opens
        let closes = await fixture.session.closes
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(opens, closes)
    }

    func testRemoteChangesAndDeletionsAreDetectedWithoutRecursiveWalk() async throws {
        let fixture = try FinderReaderFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        _ = try await reader.list(FinderPath.rootIdentifier)
        _ = try await reader.list(FinderPath.identifier("folder"))
        let anchor = await reader.currentAnchor()
        await fixture.session.changeRoot()
        try await reader.refreshKnownFolders()
        let changes = try await reader.changes(since: anchor, container: nil)
        XCTAssertEqual(changes.updated.map(\.name), ["hello.bin"])
        XCTAssertEqual(Set(changes.deleted), Set(try ["folder", "folder/child"].map(FinderPath.identifier)))
        let paths = await fixture.session.listed
        XCTAssertEqual(Set(paths), ["/home/user", "/home/user/folder"])
    }

    func testLinksAndEscapingCanonicalPathsAreNotExposed() async throws {
        let fixture = try FinderReaderFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let items = try await reader.list(FinderPath.rootIdentifier)
        XCTAssertFalse(items.contains { $0.name == "escape" })
        await fixture.session.redirectRoot()
        do {
            _ = try await reader.list(FinderPath.rootIdentifier)
            XCTFail("A changed canonical root must not be followed")
        } catch { XCTAssertEqual(error as? FinderReadError, .outsideRoot) }
    }

    func testChangedDownloadAndCancellationLeaveNoPartialFile() async throws {
        let fixture = try FinderReaderFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        let url = fixture.directory.appendingPathComponent("download.bin")
        let id = try FinderPath.identifier("hello.bin")
        _ = try await reader.list(FinderPath.rootIdentifier)
        await fixture.session.changeDuringDownload()
        do {
            _ = try await reader.download(id, version: nil, to: url) { _, _ in }
            XCTFail("Changed content must not be reported as the old version")
        } catch { XCTAssertEqual(error as? FinderReadError, .versionChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let task = Task {
            _ = try await reader.download(id, version: nil, to: url) { _, _ in }
        }
        task.cancel()
        do { try await task.value; XCTFail("Cancelled read succeeded") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCorruptIndexIsNotSilentlyReplaced() throws {
        let fixture = try FinderReaderFixture()
        defer { fixture.cleanup() }
        let data = Data("broken".utf8)
        try data.write(to: fixture.catalogURL)
        XCTAssertThrowsError(try fixture.reader())
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), data)
    }

    func testDuplicateNamesFailWithoutCrashingOrReplacingIndex() async throws {
        let fixture = try FinderReaderFixture()
        defer { fixture.cleanup() }
        let reader = try fixture.reader()
        _ = try await reader.list(FinderPath.rootIdentifier)
        let original = try Data(contentsOf: fixture.catalogURL)
        await fixture.session.duplicateNames()
        do {
            _ = try await reader.list(FinderPath.rootIdentifier)
            XCTFail("Duplicate names cannot be indexed safely")
        } catch { XCTAssertEqual(error as? FinderReadError, .unsupportedNames) }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), original)
    }
}

private struct FinderReaderFixture {
    let directory: URL
    let session: ReadOnlyFiles
    let bytes = Data((0..<80_000).map { UInt8($0 % 251) })
    var catalogURL: URL { directory.appendingPathComponent("catalog.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = ReadOnlyFiles(bytes: bytes)
    }

    func reader() throws -> FinderRemoteReader {
        try FinderRemoteReader(rootPath: "/home/user", catalogURL: catalogURL) {
            await session.open()
            return session
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

private actor ReadOnlyFiles: RemoteFileSession {
    let bytes: Data
    var opens = 0
    var closes = 0
    var writes = 0
    var listed: [String] = []
    private var changed = false
    private var redirected = false
    private var mutateDownload = false
    private var duplicated = false

    init(bytes: Data) { self.bytes = bytes }
    func open() { opens += 1 }
    func close() { closes += 1 }
    func changeRoot() { changed = true }
    func redirectRoot() { redirected = true }
    func changeDuringDownload() { mutateDownload = true }
    func duplicateNames() { duplicated = true }
    func canonicalPath(_ path: String) -> String { redirected ? "/elsewhere" : path }

    func list(_ path: String) -> [RemoteEntry] {
        listed.append(path)
        if path == "/home/user/folder" {
            return [RemoteEntry(path: path + "/child", name: "child", kind: .file, size: 3, modified: nil)]
        }
        let file = RemoteEntry(path: path + "/hello.bin", name: "hello.bin", kind: .file,
                               size: UInt64(bytes.count + (changed ? 1 : 0)), modified: nil)
        if duplicated { return [file, file] }
        if changed { return [file] }
        return [file, RemoteEntry(path: path + "/folder", name: "folder", kind: .directory, size: nil, modified: nil),
                RemoteEntry(path: path + "/escape", name: "escape", kind: .symbolicLink, size: nil, modified: nil)]
    }

    func download(_ path: String, to url: URL, progress: @escaping TransferProgress) async throws {
        try Task.checkCancellation()
        try bytes.write(to: url)
        if mutateDownload { changed = true }
        await progress(UInt64(bytes.count), UInt64(bytes.count))
    }

    func createDirectory(_ path: String) { writes += 1 }
    func rename(_ path: String, to destination: String) { writes += 1 }
    func remove(_ entry: RemoteEntry) { writes += 1 }
    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) { writes += 1 }
}
