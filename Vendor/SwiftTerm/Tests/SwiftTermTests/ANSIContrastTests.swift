import XCTest
@testable import SwiftTerm

final class ANSIContrastTests: XCTestCase {
    private func rgb(_ value: UInt32) -> SIMD3<Double> {
        SIMD3(Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    func testTmuxBlackOnGreenAndYellowRemainsReadable() {
        // Old light palette, new palette and conventional ANSI backgrounds.
        for background: UInt32 in [0x116329, 0x795E00, 0x7EE787, 0xE3B341, 0x008000, 0x808000] {
            let resolved = ANSIContrast.resolve(rgb(0x24292F), on: rgb(background))
            XCTAssertGreaterThanOrEqual(ANSIContrast.ratio(resolved, rgb(background)), 4.5)
        }
    }

    func testANSITextOnAllThemeBackgroundsKeepsContrastAndChannelOrdering() {
        let colors: [UInt32] = [0xFF7B72, 0x7EE787, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x76E3EA]
        for background: UInt32 in [0xFFFFFF, 0x1E1E1E, 0xF4F8FC, 0x101C2B, 0xFFF9EF, 0x241F19] {
            for color in colors {
                let original = rgb(color), bg = rgb(background)
                let resolved = ANSIContrast.resolve(original, on: bg)
                XCTAssertGreaterThanOrEqual(ANSIContrast.ratio(resolved, bg), 4.5)
                for a in 0..<3 {
                    for b in 0..<3 where original[a] > original[b] {
                        XCTAssertGreaterThanOrEqual(resolved[a], resolved[b])
                    }
                }
            }
        }
    }

    func testReadableAndIntentionallyHiddenTextAreUnchanged() {
        let black = rgb(0), white = rgb(0xFFFFFF)
        XCTAssertEqual(ANSIContrast.resolve(black, on: white), black)
        XCTAssertEqual(ANSIContrast.resolve(white, on: black), white)
        XCTAssertEqual(ANSIContrast.resolve(black, on: black), black)
        XCTAssertEqual(ANSIContrast.resolve(white, on: white), white)
    }
}
