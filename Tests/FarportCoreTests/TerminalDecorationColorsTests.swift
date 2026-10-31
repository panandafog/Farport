import FarportCore
import XCTest

final class TerminalDecorationColorsTests: XCTestCase {
    func testAccentTintStaysReadableAcrossAppearancesAndAccents() {
        func luminance(_ rgb: UInt32) -> Double {
            zip([16, 8, 0], [0.2126, 0.7152, 0.0722]).reduce(0) { result, item in
                let value = Double((rgb >> item.0) & 255) / 255
                return result + item.1 * (value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
            }
        }
        for dark in [false, true] {
            for background: UInt32 in [0xFFFFFF, 0x1E1E1E, 0xFFF9EF, 0x101C2B] {
                for accent: UInt32 in [0xFF8000, 0x007AFF, 0x00FF00, 0, 0xFFFFFF, 0xFF00FF] {
                    let colors = TerminalDecorationColors.tinted(background: background, accent: accent, dark: dark)
                    let foreground = luminance(colors.foreground), backgroundValue = luminance(colors.background)
                    let lighter = max(foreground, backgroundValue) + 0.05
                    let darker = min(foreground, backgroundValue) + 0.05
                    XCTAssertGreaterThanOrEqual(lighter / darker, 4.5)
                }
            }
        }
        XCTAssertNotEqual(TerminalDecorationColors.tinted(background: 0xFFFFFF, accent: 0xFF8000, dark: false),
                          TerminalDecorationColors.tinted(background: 0xFFFFFF, accent: 0x007AFF, dark: false))
    }
}
