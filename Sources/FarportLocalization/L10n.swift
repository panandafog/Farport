import Foundation

/// App and package strings share one bundle; host data and terminal output never pass through this lookup.
public enum L10n {
    static let resourceBundle = Bundle.module
    public static func text(_ key: String, _ arguments: CVarArg...) -> String {
        resolve(key, arguments: arguments, bundle: .module, locale: .current)
    }

    public static func text(_ key: String, locale: Locale, arguments: [CVarArg] = []) -> String {
        let language = Bundle.preferredLocalizations(
            from: ["en", "ru"], forPreferences: [locale.identifier]
        ).first ?? "en"
        let bundle = Bundle.module.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:))
        return resolve(key, arguments: arguments, bundle: bundle ?? .module, locale: locale)
    }

    private static func resolve(_ key: String, arguments: [CVarArg], bundle: Bundle, locale: Locale) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
}
