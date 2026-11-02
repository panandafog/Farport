import Foundation

/// Theme metadata for optional transport-owned decorations; does not remap terminal ANSI roles.
public struct TerminalDecorationColors: Equatable, Sendable {
    public let foreground: UInt32
    public let background: UInt32
    /// The unmodified application accent, separate from the tinted background.
    public let accent: UInt32?
    public let useAppAccent: Bool

    public init(foreground: UInt32, background: UInt32, accent: UInt32? = nil, useAppAccent: Bool = true) {
        self.foreground = foreground & 0xFFFFFF
        self.background = background & 0xFFFFFF
        self.accent = accent.map { $0 & 0xFFFFFF }
        self.useAppAccent = useAppAccent
    }

    public static func tinted(background: UInt32, accent: UInt32, dark: Bool, useAppAccent: Bool = true) -> Self {
        let fraction = dark ? 0.28 : 0.18
        var tinted: UInt32 = 0
        var luminance = 0.0
        for (shift, weight) in [(16, 0.2126), (8, 0.7152), (0, 0.0722)] {
            let base = Double((background >> shift) & 255)
            let color = Double((accent >> shift) & 255)
            let channel = UInt32((base + (color - base) * fraction).rounded())
            tinted |= channel << shift
            let value = Double(channel) / 255
            luminance += weight * (value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
        }
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return Self(foreground: blackContrast >= whiteContrast ? 0 : 0xFFFFFF, background: tinted,
                    accent: accent, useAppAccent: useAppAccent)
    }
}
