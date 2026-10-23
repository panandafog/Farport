import AppKit
@testable import Harbor
import XCTest

@MainActor
final class AccentColorTests: XCTestCase {
    func testAppBundleIncludesAccentForBothAppearances() throws {
        let bundle = Bundle(for: LibraryModel.self)
        let accent = try XCTUnwrap(NSColor(named: "AccentColor", bundle: bundle))
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolved = accent.usingColorSpace(.sRGB)
            }
            XCTAssertEqual(try XCTUnwrap(resolved).alphaComponent, 1, accuracy: 0.001)
        }
    }
}
