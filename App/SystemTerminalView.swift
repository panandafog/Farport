import AppKit
import SwiftTerm

struct TerminalPalette {
    let dark: Bool

    var ansi: [SwiftTerm.Color] {
        let values: [UInt32] = dark ? [
            0x24292F, 0xFF7B72, 0x7EE787, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x76E3EA, 0xB1BAC4,
            0x6E7681, 0xFFA198, 0xA5F3B4, 0xF2CC60, 0xA5D6FF, 0xE2C5FF, 0xB3F0F3, 0xF0F6FC
        ] : [
            0x24292F, 0xB42318, 0x116329, 0x795E00, 0x0550AE, 0x6E40AA, 0x006B73, 0x6E7781,
            0x57606A, 0xCF222E, 0x1A7F37, 0x896400, 0x0969DA, 0x8250DF, 0x007A83, 0x424A53
        ]
        return values.map {
            SwiftTerm.Color(red: UInt16(($0 >> 16) & 0xFF) * 257,
                            green: UInt16(($0 >> 8) & 0xFF) * 257,
                            blue: UInt16($0 & 0xFF) * 257)
        }
    }

    var selection: NSColor {
        dark ? NSColor(srgbRed: 0.18, green: 0.26, blue: 0.36, alpha: 1) :
            NSColor(srgbRed: 0.83, green: 0.90, blue: 1, alpha: 1)
    }
}

final class SystemTerminalView: TerminalView {
    private var appliedAppearance: NSAppearance.Name?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySystemTheme()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applySystemTheme()
    }

    func applySystemTheme() {
        guard terminal != nil else { return }
        let appearance = effectiveAppearance
        guard appliedAppearance != appearance.name else { return }
        appliedAppearance = appearance.name
        let palette = TerminalPalette(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        appearance.performAsCurrentDrawingAppearance {
            // Resolve dynamic AppKit colors before SwiftTerm converts them to RGB values.
            nativeBackgroundColor = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .textBackgroundColor
            nativeForegroundColor = NSColor.textColor.usingColorSpace(.sRGB) ?? .textColor
            caretColor = nativeForegroundColor
            caretTextColor = nativeBackgroundColor
            selectedTextBackgroundColor = palette.selection
            installColors(palette.ansi)
            layer?.backgroundColor = nativeBackgroundColor.cgColor
        }
        needsDisplay = true
    }
}
