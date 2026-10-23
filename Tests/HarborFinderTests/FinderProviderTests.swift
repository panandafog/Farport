#if os(macOS)
import FileProvider
import HarborCore
import HarborFinder
import XCTest

final class FinderProviderTests: XCTestCase {
    func testReadOnlyCapabilitiesAndRootMapping() throws {
        let root = FinderProviderItem(try FinderItem(relativePath: "", isDirectory: true), rootName: "Test")
        XCTAssertEqual(root.itemIdentifier, .rootContainer)
        XCTAssertEqual(root.filename, "Test")
        XCTAssertEqual(root.contentType, .folder)
        XCTAssertTrue(root.capabilities.contains(.allowsContentEnumerating))
        XCTAssertFalse(root.capabilities.contains(.allowsAddingSubItems))
        let file = FinderProviderItem(try FinderItem(relativePath: "test.bin", isDirectory: false), rootName: "Test")
        XCTAssertEqual(file.parentItemIdentifier, .rootContainer)
        XCTAssertEqual(file.capabilities, [.allowsReading])
        XCTAssertLessThanOrEqual(file.itemVersion.contentVersion.count, 128)
        XCTAssertLessThanOrEqual(file.itemVersion.metadataVersion.count, 128)
    }

    func testErrorsPreserveSystemMeaningAndNeverReportOfflineAsMissing() {
        for (error, code) in [(FinderReadError.noSuchItem, NSFileProviderError.Code.noSuchItem),
                               (.versionChanged, .versionNoLongerAvailable), (.anchorExpired, .syncAnchorExpired),
                               (.timedOut, .serverUnreachable), (.disabled, .notAuthenticated)] {
            let translated = FinderProviderError.translate(error) as NSError
            XCTAssertEqual(translated.domain, NSFileProviderErrorDomain)
            XCTAssertEqual(translated.code, code.rawValue)
        }
        let offline = FinderProviderError.translate(HarborError.message("Transport lost")) as NSError
        XCTAssertEqual(offline.code, NSFileProviderError.serverUnreachable.rawValue)
        let page = NSFileProviderError(.pageExpired)
        XCTAssertEqual(FinderProviderError.translate(page) as NSError, page as NSError)
        XCTAssertEqual((FinderProviderError.translate(CancellationError()) as NSError).code,
                       CocoaError.userCancelled.rawValue)
    }
}
#endif
