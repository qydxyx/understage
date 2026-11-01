import Foundation

enum L10n {
    static var prefersChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    static func prefersChinese(for query: String) -> Bool {
        prefersChinese || query.unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) }
    }

    static func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    static func format(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        let template = String(localized: key)
        return String(format: template, locale: Locale.current, arguments: args)
    }
}
