import FarportCore
import FarportFinder
import FileProvider
import XCTest

final class FinderExtensionTests: XCTestCase {
    func testAllMutationCallbacksRejectWritesEvenWithUnconfiguredDomain() throws {
        let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(UUID().uuidString),
                                          displayName: "Unit Test")
        let provider = FileProviderExtension(domain: domain)
        defer { provider.invalidate() }
        let item = FinderProviderItem(try FinderItem(relativePath: "file.txt", isDirectory: false), rootName: "Test")
        let request = NSFileProviderRequest()
        var callbacks = 0
        _ = provider.createItem(basedOn: item, fields: [.filename, .contents], contents: nil,
                                options: [], request: request) { result, _, _, error in
            XCTAssertNil(result)
            XCTAssertEqual((error as NSError?)?.code, CocoaError.fileWriteNoPermission.rawValue)
            callbacks += 1
        }
        _ = provider.modifyItem(item, baseVersion: item.itemVersion, changedFields: [.filename], contents: nil,
                                options: [], request: request) { result, _, _, error in
            XCTAssertNil(result)
            XCTAssertEqual((error as NSError?)?.code, CocoaError.fileWriteNoPermission.rawValue)
            callbacks += 1
        }
        _ = provider.deleteItem(identifier: item.itemIdentifier, baseVersion: item.itemVersion,
                                options: [], request: request) { error in
            XCTAssertEqual((error as NSError?)?.code, CocoaError.fileWriteNoPermission.rawValue)
            callbacks += 1
        }
        XCTAssertEqual(callbacks, 3)
        XCTAssertThrowsError(try provider.enumerator(for: .trashContainer, request: request))
    }

    func testEnumerationPaginatesOneSnapshotAndRejectsExpiredPage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = EnumerationFiles()
        let reader = try FinderRemoteReader(rootPath: "/", catalogURL: directory.appendingPathComponent("index.json")) {
            files
        }
        let enumerator = FinderEnumerator(container: .rootContainer, reader: reader, rootName: "Test")
        defer { enumerator.invalidate() }
        var page = NSFileProviderPage(NSFileProviderPage.initialPageSortedByName as Data)
        var identifiers: [NSFileProviderItemIdentifier] = []
        for expectedCount in [100, 100, 50] {
            let observer = EnumerationObserver(done: expectation(description: "Enumeration page"))
            enumerator.enumerateItems(for: observer, startingAt: page)
            await fulfillment(of: [observer.done], timeout: 5)
            XCTAssertNil(observer.error)
            XCTAssertEqual(observer.items.count, expectedCount)
            identifiers += observer.items.map(\.itemIdentifier)
            if let next = observer.next { page = next } else { XCTAssertEqual(expectedCount, 50) }
        }
        XCTAssertEqual(Set(identifiers).count, 250)
        let count = await files.listCount
        XCTAssertEqual(count, 1)
        let expired = EnumerationObserver(done: expectation(description: "Expired page"))
        enumerator.enumerateItems(for: expired, startingAt: NSFileProviderPage(Data("expired".utf8)))
        await fulfillment(of: [expired.done], timeout: 5)
        XCTAssertEqual((expired.error as NSError?)?.code, NSFileProviderError.pageExpired.rawValue)
    }
}

private final class EnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
    let done: XCTestExpectation
    var items: [NSFileProviderItem] = []
    var next: NSFileProviderPage?
    var error: Error?

    init(done: XCTestExpectation) { self.done = done }
    func didEnumerate(_ updatedItems: [NSFileProviderItem]) { items += updatedItems }
    func finishEnumerating(upTo nextPage: NSFileProviderPage?) { next = nextPage; done.fulfill() }
    func finishEnumeratingWithError(_ error: Error) { self.error = error; done.fulfill() }
}

private actor EnumerationFiles: RemoteFileSession {
    var listCount = 0
    func canonicalPath(_ path: String) -> String { path }
    func list(_ path: String) -> [RemoteEntry] {
        listCount += 1
        return (0..<250).map {
            RemoteEntry(path: "/\($0).txt", name: "\($0).txt", kind: .file, size: 4, modified: nil)
        }
    }
    func close() { }
    func createDirectory(_ path: String) { XCTFail("Read-only provider attempted mkdir") }
    func rename(_ path: String, to destination: String) { XCTFail("Read-only provider attempted rename") }
    func remove(_ entry: RemoteEntry) { XCTFail("Read-only provider attempted delete") }
    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) { }
    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) { XCTFail("Attempted upload") }
}
