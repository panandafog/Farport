import FarportCore
import FarportSSH
import XCTest

final class FinderWriteIntegrationTests: XCTestCase {
    func testAtomicSaveRenameAndDeleteThroughProxyJump() async throws {
        let fixture = try JumpTestFixture()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        let reader = try FinderRemoteReader(rootPath: "/", catalogURL: local.appendingPathComponent("catalog.json"),
                                             writable: true) { try await fixture.provider.files(for: fixture.target) }
        let source = local.appendingPathComponent("source.bin")
        let original = Data((0..<120_000).map { UInt8($0 % 251) })
        try original.write(to: source)
        let request = FinderCreateRequest(token: UUID().uuidString, parentIdentifier: FinderPath.rootIdentifier,
                                           name: "finder-\(UUID().uuidString).bin", isDirectory: false,
                                           contents: source)
        let created = try await reader.create(request, progress: { _, _ in })
        let item = try XCTUnwrap(created)
        let edited = Data((0..<180_000).map { UInt8($0 % 127) })
        try edited.write(to: source)
        let result = try await reader.modify(FinderModifyRequest(identifier: item.identifier,
            baseVersion: item.contentVersion, contents: source), progress: { _, _ in })
        XCTAssertFalse(result.refetchContents)
        let download = local.appendingPathComponent("download.bin")
        _ = try await reader.download(item.identifier, version: nil, to: download) { _, _ in }
        XCTAssertEqual(try Data(contentsOf: download), edited)
        let moved = try await reader.modify(FinderModifyRequest(identifier: item.identifier,
            baseVersion: result.item.contentVersion, name: "moved-\(UUID().uuidString).bin"), progress: { _, _ in })
        XCTAssertEqual(moved.item.identifier, item.identifier)
        try await reader.delete(item.identifier, baseVersion: moved.item.contentVersion)
        let entries = try await reader.list(FinderPath.rootIdentifier)
        XCTAssertFalse(entries.contains { $0.identifier == item.identifier })
        XCTAssertFalse(entries.contains { $0.name.contains(".harbor-") })
        try await fixture.waitClosed()
        XCTAssertEqual(try fixture.stats().shells, 0)
    }

    func testStaleContentHashCannotReplaceOriginalAndCancellationCleansStaging() async throws {
        let fixture = try JumpTestFixture()
        let session = try await fixture.provider.files(for: fixture.target)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        let source = local.appendingPathComponent("source.bin")
        let original = Data(repeating: 97, count: 200_000)
        try original.write(to: source)
        let path = "/replace-\(UUID().uuidString).bin"
        do {
            try await session.upload(source, to: path) { _, _ in }
            let listing = try await session.list("/")
            let item = try XCTUnwrap(listing.first { $0.path == path })
            let replacing = try XCTUnwrap(session as? any RemoteFileReplacingSession)
            let stale = RemoteFileRevision(size: item.size, modified: item.modified,
                                           digest: Data(repeating: 0, count: 32))
            do {
                try await replacing.replaceContents(source, at: path, expected: stale) { _, _ in }
                XCTFail("Stale digest replaced a file")
            } catch FinderWriteError.conflict { }
            let expected = RemoteFileRevision(size: item.size, modified: item.modified,
                                              digest: try FileDigest.sha256(source))
            try Data(repeating: 98, count: 400_000).write(to: source)
            let started = TransferStarted()
            let task = Task {
                try await replacing.replaceContents(source, at: path, expected: expected) { completed, _ in
                    if completed > 0 { await started.mark() }
                    try? await Task.sleep(for: .milliseconds(15))
                }
            }
            try await fixture.wait { await started.value }
            task.cancel()
            do { try await task.value; XCTFail("Cancelled upload succeeded") } catch { }
            let download = local.appendingPathComponent("download.bin")
            try await session.download(path, to: download) { _, _ in }
            XCTAssertEqual(try Data(contentsOf: download), original)
            let remaining = try await session.list("/")
            XCTAssertFalse(remaining.contains { $0.path.hasPrefix(path + ".harbor-") })
            try await session.remove(item)
            await session.close()
            try await fixture.waitClosed()
        } catch { await session.close(); throw error }
    }
}

private actor TransferStarted {
    var value = false
    func mark() { value = true }
}
