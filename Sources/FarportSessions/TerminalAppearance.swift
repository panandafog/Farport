public enum TerminalColorScheme: String, CaseIterable, Sendable {
    case standard, ocean, paper

    public func background(dark: Bool) -> UInt32 {
        switch self {
        case .standard: dark ? 0x1E1E1E : 0xFFFFFF
        case .ocean: dark ? 0x101C2B : 0xF4F8FC
        case .paper: dark ? 0x241F19 : 0xFFF9EF
        }
    }

    public func foreground(dark: Bool) -> UInt32 {
        switch self {
        case .standard: dark ? 0xFFFFFF : 0x000000
        case .ocean: dark ? 0xDCEAF7 : 0x20344B
        case .paper: dark ? 0xF2E6D3 : 0x403326
        }
    }

    public func accent(dark: Bool) -> UInt32 {
        switch self {
        case .standard: dark ? 0x79C0FF : 0x0550AE // Native adapters supply the system accent.
        case .ocean: dark ? 0x6CCCE8 : 0x087DA1
        case .paper: dark ? 0xE8B878 : 0x986019
        }
    }
}

public struct TerminalAppearance: Equatable, Sendable {
    public var scheme: TerminalColorScheme
    public var followsSystem: Bool
    public var dark: Bool
    public var useAppAccent: Bool

    public init(scheme: TerminalColorScheme = .standard, followsSystem: Bool = true, dark: Bool = true,
                useAppAccent: Bool = true) {
        self.scheme = scheme
        self.followsSystem = followsSystem
        self.dark = dark
        self.useAppAccent = useAppAccent
    }

    public func usesDarkColors(systemDark: Bool) -> Bool { followsSystem ? systemDark : dark }
}
