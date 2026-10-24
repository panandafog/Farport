@testable import Farport
import Foundation
import XCTest

final class BrandingTests: XCTestCase {
    func testProductRenamePreservesApplicationIdentity() throws {
        let bundle = Bundle(for: LibraryModel.self)
        XCTAssertTrue(String(reflecting: LibraryModel.self).hasPrefix("Farport."))
        XCTAssertEqual(bundle.bundleIdentifier, "com.panandafog.harbor")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Farport")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, "Farport")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "Farport")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "HarborCloudContainer") as? String,
                       "iCloud.com.panandafog.harbor")
        let group = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "HarborAppGroup") as? String)
        XCTAssertTrue(group.hasPrefix("group.dev.harbor.shared."))
        let keychain = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "HarborKeychainGroup") as? String)
        XCTAssertTrue(keychain.hasSuffix("dev.harbor.shared"))
        let plugins = try XCTUnwrap(bundle.builtInPlugInsURL)
        let finder = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("FarportFinderExtension.appex")))
        XCTAssertEqual(finder.bundleIdentifier, "com.panandafog.harbor.finder")
        XCTAssertEqual(finder.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "FarportFinderExtension")
        XCTAssertEqual(finder.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Farport Files")
        XCTAssertEqual(finder.object(forInfoDictionaryKey: "HarborAppGroup") as? String, group)
        XCTAssertEqual(finder.object(forInfoDictionaryKey: "HarborKeychainGroup") as? String, keychain)
    }
}
