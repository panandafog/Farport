import FileProvider
import HarborCore
import HarborFinder
import XCTest

final class FinderWriteCallbackTests: XCTestCase {
    func testWritableCallbacksAcknowledgeOnlyRemoteSuccessAndReturnStableIdentifier() async throws {
        let fixture = try FinderWriteFixture()
        defer { fixture.cleanup() }
        let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(UUID().uuidString),
                                          displayName: "Test")
        let provider = FileProviderExtension(domain: domain, reader: .success(try fixture.reader()), writable: true)
        defer { provider.invalidate() }
        let template = FinderProviderItem(try FinderItem(relativePath: "callback.txt", isDirectory: false),
                                           rootName: "Test")
        let contents = try fixture.source("Created through File Provider")
        let created = try await create(template, url: contents, provider: provider)
        XCTAssertTrue(created.capabilities.contains(.allowsWriting))
        XCTAssertEqual(try String(contentsOf: fixture.remote.appendingPathComponent("callback.txt"), encoding: .utf8),
                       "Created through File Provider")
        let changed = try fixture.source("Edited through File Provider")
        let updated: NSFileProviderItem = try await withCheckedThrowingContinuation { continuation in
            _ = provider.modifyItem(
                created, baseVersion: created.itemVersion, changedFields: [.contents],
                contents: changed, options: [], request: NSFileProviderRequest()
            ) { item, _, _, error in
                if let error { continuation.resume(throwing: error) } else if let item {
                    continuation.resume(returning: item)
                } else { continuation.resume(throwing: HarborError.message("Missing modified item")) }
            }
        }
        XCTAssertEqual(updated.itemIdentifier, created.itemIdentifier)
        XCTAssertEqual(try String(contentsOf: fixture.remote.appendingPathComponent("callback.txt"), encoding: .utf8),
                       "Edited through File Provider")
        let version = try XCTUnwrap(updated.itemVersion)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = provider.deleteItem(identifier: updated.itemIdentifier, baseVersion: version,
                                      options: [], request: NSFileProviderRequest()) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        let remote = fixture.remote.appendingPathComponent("callback.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: remote.path))
    }

    private func create(_ template: FinderProviderItem, url: URL,
                        provider: FileProviderExtension) async throws -> FinderProviderItem {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.createItem(
                basedOn: template, fields: [.filename, .contents, .parentItemIdentifier],
                contents: url, options: [], request: NSFileProviderRequest()
            ) { item, _, _, error in
                if let error { continuation.resume(throwing: error) } else if let item = item as? FinderProviderItem {
                    continuation.resume(returning: item)
                } else { continuation.resume(throwing: HarborError.message("Missing created item")) }
            }
        }
    }
}
