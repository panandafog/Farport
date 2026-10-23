import Foundation
@testable import HarborCore
import XCTest

final class FinderCatalogTests: XCTestCase {
    func testIdentifiersRoundTripUnicodeAndRejectTraversal() throws {
        for path in ["", "hello.txt", "folder/sp ace/тест.txt", "a\\b", "#?%"] {
            XCTAssertEqual(try FinderPath.relativePath(FinderPath.identifier(path)), path)
        }
        for path in ["/etc/passwd", "../etc", "a/../../etc", "a//b", "a/./b", "a/", "a\0b"] {
            XCTAssertThrowsError(try FinderPath.identifier(path))
            let forged = "path." + Data(path.utf8).base64EncodedString()
            XCTAssertThrowsError(try FinderPath.relativePath(forged))
        }
        XCTAssertEqual(try FinderPath.remotePath("file", root: "/home/user"), "/home/user/file")
        XCTAssertEqual(try FinderPath.remotePath("file", root: "/"), "/file")
        XCTAssertThrowsError(try FinderPath.validateRoot("/home/user/.."))
        XCTAssertThrowsError(try FinderPath.validateRoot("/home/user/"))
    }

    func testChangesAreDurableScopedAndIncludeDeletedDescendants() throws {
        var catalog = FinderCatalog(rootPath: "/home/user")
        let initial = catalog.anchor
        let folder = try FinderItem(relativePath: "folder", isDirectory: true)
        let child = try FinderItem(relativePath: "folder/file", isDirectory: false, size: 8)
        catalog.reconcile([folder], in: "")
        catalog.reconcile([child], in: "folder")
        let saved = try JSONDecoder().decode(FinderCatalog.self, from: JSONEncoder().encode(catalog))
        XCTAssertEqual(try saved.changes(since: initial, container: nil).updated.count, 2)
        XCTAssertEqual(try saved.changes(since: initial, container: "folder").updated.count, 2)
        let anchor = catalog.anchor
        catalog.reconcile([], in: "")
        let changes = try catalog.changes(since: anchor, container: nil)
        XCTAssertEqual(Set(changes.deleted), Set([folder.identifier, child.identifier]))
        XCTAssertTrue(catalog.allItems.isEmpty)
        XCTAssertThrowsError(try catalog.changes(since: Data("bad-anchor".utf8), container: nil))
    }

    func testUnchangedPollDoesNotAdvanceAnchorAndOldJournalExpires() throws {
        var catalog = FinderCatalog(rootPath: "/")
        let initial = catalog.anchor
        for value in 0..<4_100 {
            catalog.reconcile([try FinderItem(relativePath: "file", isDirectory: false, size: UInt64(value))], in: "")
        }
        XCTAssertLessThanOrEqual(catalog.journal.count, 4_000)
        XCTAssertThrowsError(try catalog.changes(since: initial, container: nil))
        let anchor = catalog.anchor
        catalog.reconcile(catalog.folders[""] ?? [], in: "")
        XCTAssertEqual(anchor, catalog.anchor)
    }

    func testLocationContainsOnlySelectedRouteAndUsesPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gateway = SavedHost(profile: HostProfile(hostname: "gateway", username: "jump"))
        let target = SavedHost(profile: HostProfile(hostname: "private", username: "user", jumpHostIDs: [gateway.id]))
        let unrelated = SavedHost(profile: HostProfile(hostname: "unrelated", username: "other"))
        let location = try FinderLocation(host: target, library: [gateway, target, unrelated], rootPath: "/home/user")
        XCTAssertEqual(location.hosts.map(\.id), [gateway.id, target.id])
        let repository = FinderLocationRepository(directory: directory)
        try repository.save(location)
        XCTAssertEqual(try repository.load(location.id), location)
        XCTAssertEqual(try repository.loadAll(), [location])
        let file = directory.appendingPathComponent(location.id.uuidString + ".json")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        try repository.remove(location.id)
        XCTAssertTrue(try repository.loadAll().isEmpty)
        XCTAssertThrowsError(try repository.load(location.id))
    }
}
