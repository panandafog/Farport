import FarportSessions
import XCTest

final class TerminalKeyboardInputTests: XCTestCase {
    func testEveryControlLetterAndAlreadyTranslatedEvent() {
        for byte in UInt8(1)...26 {
            for scalar in [byte + 64, byte + 96, byte] {
                XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: String(UnicodeScalar(scalar))), [byte])
            }
        }
    }

    func testCommonShellControlsAndMetaControl() {
        for (key, byte): (String, UInt8) in [("c", 3), ("d", 4), ("z", 26), ("a", 1), ("e", 5),
                                           ("u", 21), ("w", 23), ("l", 12), ("r", 18), ("b", 2)] {
            XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: key), [byte])
            XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: key, meta: true), [27, byte])
        }
    }

    func testNonLatinLayoutUsesPhysicalKeyButLatinLayoutKeepsItsOwnMapping() {
        XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: "\u{441}", fallback: "c"), [3])
        XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: "\u{43a}", fallback: "r"), [18])
        XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: "j", fallback: "c"), [10])
        XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: "\u{421}"), [3])
        XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: "\u{441}"), [3])
        XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: "\u{43a}", fallback: "c"), [3])
    }

    func testControlPunctuationAndNumberAliases() {
        for (keys, byte): ([String], UInt8) in [([" ", "@", "2"], 0), (["[", "3"], 27),
                                              (["\\", "4"], 28), (["]", "5"], 29), (["^", "6"], 30),
                                              (["_", "7"], 31), (["?", "8"], 127)] {
            for key in keys { XCTAssertEqual(TerminalKeyboardInput.controlSequence(characters: key), [byte]) }
        }
    }

    func testOtherKeysRemainWithNativeTerminalHandler() {
        for key in ["", "ab", "\u{f700}", "9", ".", "\u{1f600}"] {
            XCTAssertNil(TerminalKeyboardInput.controlSequence(characters: key))
        }
    }

    func testRegisteredShortcutCharactersAreUniqueAndEncodable() {
        let characters = TerminalKeyboardInput.shortcutCharacters
        XCTAssertEqual(Set(characters).count, characters.count)
        XCTAssertTrue(characters.allSatisfy { TerminalKeyboardInput.controlSequence(characters: $0) != nil })
    }
}
