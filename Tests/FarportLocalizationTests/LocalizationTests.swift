@testable import FarportLocalization
import XCTest

final class LocalizationTests: XCTestCase {
    func testEveryEnglishKeyHasRussianTextAndMatchingFormatArguments() throws {
        let english = try strings("en")
        let russian = try strings("ru")
        XCTAssertEqual(Set(english.keys), Set(russian.keys))
        XCTAssertGreaterThan(english.count, 200)
        let placeholders = try NSRegularExpression(pattern: "%(@|lld)")
        for (key, value) in english {
            let translation = try XCTUnwrap(russian[key], key)
            XCTAssertFalse(translation.isEmpty, key)
            func formats(_ text: String) -> [String] {
                placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                    (text as NSString).substring(with: $0.range)
                }
            }
            XCTAssertEqual(formats(value), formats(translation), key)
        }
    }

    func testLocaleFallbackAndDynamicValues() {
        XCTAssertEqual(L10n.text("Connect", locale: Locale(identifier: "ru_RU")), "Подключить")
        XCTAssertEqual(L10n.text("Connect", locale: Locale(identifier: "en_US")), "Connect")
        XCTAssertEqual(L10n.text("Connect", locale: Locale(identifier: "de_DE")), "Connect")
        XCTAssertEqual(L10n.text("Delete '%@'?", locale: Locale(identifier: "ru"), arguments: ["100% server"]),
                       "Удалить «100% server»?")
        XCTAssertEqual(L10n.text("Terminal %lld", locale: Locale(identifier: "ru"), arguments: [Int64(2)]),
                       "Терминал 2")
    }

    private func strings(_ language: String) throws -> [String: String] {
        let directory = try XCTUnwrap(L10n.resourceBundle.url(forResource: language, withExtension: "lproj"))
        let data = try Data(contentsOf: directory.appendingPathComponent("Localizable.strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }
}
