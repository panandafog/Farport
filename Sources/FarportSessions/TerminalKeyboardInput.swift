public enum TerminalKeyboardInput {
    public static let shortcutCharacters = Array("abcdefghijklmnopqrstuvwxyz@[\\]^_ ?2345678").map(String.init) +
        russianControlKeys.keys.sorted()

    /// Use the physical Latin key only when the active layout cannot express a control character.
    public static func controlSequence(characters: String, fallback: String? = nil, meta: Bool = false) -> [UInt8]? {
        guard let byte = controlByte(characters) ?? fallback.flatMap(controlByte) ??
            russianControlKeys[characters.lowercased()] else { return nil }
        return meta ? [0x1b, byte] : [byte]
    }

    // UIKit key commands expose characters rather than physical key codes. Match the supported Russian layout.
    private static let russianControlKeys: [String: UInt8] = [
        "\u{444}": 1, "\u{438}": 2, "\u{441}": 3, "\u{432}": 4, "\u{443}": 5, "\u{430}": 6,
        "\u{43f}": 7, "\u{440}": 8, "\u{448}": 9, "\u{43e}": 10, "\u{43b}": 11, "\u{434}": 12,
        "\u{44c}": 13, "\u{442}": 14, "\u{449}": 15, "\u{437}": 16, "\u{439}": 17, "\u{43a}": 18,
        "\u{44b}": 19, "\u{435}": 20, "\u{433}": 21, "\u{43c}": 22, "\u{446}": 23, "\u{447}": 24,
        "\u{43d}": 25, "\u{44f}": 26, "\u{445}": 27, "\u{44a}": 29
    ]

    private static func controlByte(_ characters: String) -> UInt8? {
        guard characters.unicodeScalars.count == 1, let scalar = characters.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0...31, 127: return UInt8(scalar.value)
        case 64...95, 97...122: return UInt8(scalar.value & 0x1f)
        case 32, 50: return 0
        case 51...55: return UInt8(scalar.value - 24)
        case 63, 56: return 0x7f
        default: return nil
        }
    }
}
