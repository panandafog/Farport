import FarportSessions
import SwiftTerm
#if os(macOS)
import AppKit
typealias TerminalNativeColor = NSColor
#else
import UIKit
typealias TerminalNativeColor = UIColor
#endif

struct TerminalResolvedPalette: Equatable {
    let scheme: TerminalColorScheme
    let dark: Bool
    let background: TerminalNativeColor
    let foreground: TerminalNativeColor
    let accent: TerminalNativeColor

    var selection: TerminalNativeColor {
        #if os(macOS)
        background.blended(withFraction: dark ? 0.35 : 0.22, of: accent) ?? background
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var accentRed: CGFloat = 0, accentGreen: CGFloat = 0, accentBlue: CGFloat = 0
        background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        accent.getRed(&accentRed, green: &accentGreen, blue: &accentBlue, alpha: &alpha)
        let fraction: CGFloat = dark ? 0.35 : 0.22
        return UIColor(red: red + (accentRed - red) * fraction,
                       green: green + (accentGreen - green) * fraction,
                       blue: blue + (accentBlue - blue) * fraction, alpha: 1)
        #endif
    }

    static func color(_ rgb: UInt32) -> TerminalNativeColor {
        TerminalNativeColor(red: CGFloat((rgb >> 16) & 255) / 255,
                            green: CGFloat((rgb >> 8) & 255) / 255,
                            blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

extension TerminalView {
    func installTheme(_ palette: TerminalResolvedPalette) {
        nativeBackgroundColor = palette.background
        nativeForegroundColor = palette.foreground
        caretColor = palette.accent
        caretTextColor = palette.background
        selectedTextBackgroundColor = palette.selection
        installColors(TerminalPalette(dark: palette.dark, scheme: palette.scheme).ansi)
    }
}
