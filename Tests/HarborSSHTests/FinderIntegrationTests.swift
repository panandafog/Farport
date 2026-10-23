import HarborCore
import HarborSSH
import XCTest

final class FinderIntegrationTests: XCTestCase {
    func testFinderReaderDownloadsThroughProxyJumpWithoutGatewayShellOrServerWrites() async throws {
        let fixture = try JumpTestFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = try FinderRemoteReader(rootPath: "/", catalogURL: directory.appendingPathComponent("index.json")) {
            try await fixture.provider.files(for: fixture.target)
        }
        let initial = try await reader.list(FinderPath.rootIdentifier)
        let item = try XCTUnwrap(initial.first { $0.name == "hello.txt" })
        let url = directory.appendingPathComponent("hello.txt")
        _ = try await reader.download(item.identifier, version: item.contentVersion, to: url) { _, _ in }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Hello from Harbor's isolated SFTP fixture.\n")
        let anchor = await reader.currentAnchor()
        try await reader.refreshKnownFolders()
        let changes = try await reader.changes(since: anchor, container: nil)
        XCTAssertTrue(changes.updated.isEmpty)
        XCTAssertTrue(changes.deleted.isEmpty)
        try await fixture.waitClosed()
        XCTAssertEqual(try fixture.stats().shells, 0)
        XCTAssertTrue(try fixture.stats().destinations.contains("build.internal"))
    }
}
