import FarportSessions
import SwiftTerm
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TerminalPalette {
    let dark: Bool
    var scheme: TerminalColorScheme = .standard

    var ansi: [SwiftTerm.Color] {
        // ANSI colors are used as both foregrounds and backgrounds by remote TUIs.
        // Keep their roles stable across appearances; the renderer resolves text contrast.
        let values: [UInt32] = [
            0x24292F, 0xFF7B72, 0x7EE787, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x76E3EA, 0xB1BAC4,
            0x6E7681, 0xFFA198, 0xA5F3B4, 0xF2CC60, 0xA5D6FF, 0xE2C5FF, 0xB3F0F3, 0xF0F6FC
        ]
        return values.map {
            SwiftTerm.Color(red: UInt16(($0 >> 16) & 0xFF) * 257,
                            green: UInt16(($0 >> 8) & 0xFF) * 257,
                            blue: UInt16($0 & 0xFF) * 257)
        }
    }

    #if os(macOS)
    var selection: NSColor {
        dark ? NSColor(srgbRed: 0.18, green: 0.26, blue: 0.36, alpha: 1) :
            NSColor(srgbRed: 0.83, green: 0.90, blue: 1, alpha: 1)
    }
    #else
    var selection: UIColor {
        dark ? UIColor(red: 0.18, green: 0.26, blue: 0.36, alpha: 1) :
            UIColor(red: 0.83, green: 0.90, blue: 1, alpha: 1)
    }
    #endif
}
