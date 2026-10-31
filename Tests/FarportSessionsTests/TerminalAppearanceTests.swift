import FarportSessions
import XCTest

final class TerminalAppearanceTests: XCTestCase {
    func testManualAppearanceDoesNotChangeWithSystem() {
        for dark in [false, true] {
            let manual = TerminalAppearance(followsSystem: false, dark: dark)
            XCTAssertEqual(manual.usesDarkColors(systemDark: false), dark)
            XCTAssertEqual(manual.usesDarkColors(systemDark: true), dark)
            let automatic = TerminalAppearance(followsSystem: true, dark: dark)
            XCTAssertFalse(automatic.usesDarkColors(systemDark: false))
            XCTAssertTrue(automatic.usesDarkColors(systemDark: true))
        }
    }

    func testSchemeForegroundAndCursorContrast() {
        func luminance(_ rgb: UInt32) -> Double {
            let components = [16, 8, 0].map { shift -> Double in
                let value = Double((rgb >> shift) & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
        }
        for scheme in TerminalColorScheme.allCases {
            for dark in [false, true] {
                let background = luminance(scheme.background(dark: dark))
                for (color, minimum) in [(scheme.foreground(dark: dark), 7.0), (scheme.accent(dark: dark), 3.0)] {
                    let value = luminance(color)
                    XCTAssertGreaterThan((max(value, background) + 0.05) / (min(value, background) + 0.05), minimum)
                }
            }
        }
    }
}
