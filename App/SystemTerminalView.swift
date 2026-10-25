import AppKit
import SwiftTerm

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
