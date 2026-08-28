import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var nativeTitle: String {
        switch self {
        case .system: return "跟随系统"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    @Published private(set) var language: AppLanguage

    private let defaults: UserDefaults
    private let preferenceKey = "app.language.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: preferenceKey)
            .flatMap(AppLanguage.init(rawValue:))
            ?? .system
        L10n.setLanguage(language == .system ? nil : language.rawValue)
    }

    func setLanguage(_ language: AppLanguage) {
        guard language != self.language else { return }
        if language == .system {
            defaults.removeObject(forKey: preferenceKey)
            L10n.setLanguage(nil)
        } else {
            defaults.set(language.rawValue, forKey: preferenceKey)
            L10n.setLanguage(language.rawValue)
        }
        self.language = language
    }
}

enum L10n {
    private static let lock = NSLock()
    private static var languageCode: String?

    static func setLanguage(_ languageCode: String?) {
        lock.lock()
        self.languageCode = languageCode
        lock.unlock()
    }

    static func text(_ key: String) -> String {
        let localized = localizationBundle.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
        guard localized == key else { return localized }
        if let language = selectedLanguageCode,
           !language.hasPrefix("zh"),
           language != "en",
           let englishPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let englishBundle = Bundle(path: englishPath) {
            let english = englishBundle.localizedString(
                forKey: key,
                value: key,
                table: "Localizable"
            )
            if english != key { return english }
        }
        return sourceValue(for: key)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: locale,
            arguments: arguments
        )
    }

    static var locale: Locale {
        selectedLanguageCode.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(locale)
        )
    }

    /// Localizes provider-generated text while retaining server- or OS-provided
    /// details that are not part of CodeUsage's translation catalog.
    static func userFacing(_ value: String) -> String {
        let localized = text(value)
        if localized != value || preferredLanguage.hasPrefix("zh-Hans") {
            return localized
        }

        if let range = value.range(of: "（HTTP ", options: .backwards),
           value.hasSuffix("）") {
            let prefix = String(value[..<range.lowerBound])
            let detail = String(value[range.upperBound..<value.index(before: value.endIndex)])
            return format("error.http", text(prefix), detail)
        }
        if let range = value.range(of: "（状态码 ", options: .backwards),
           value.hasSuffix("）") {
            let prefix = String(value[..<range.lowerBound])
            let detail = String(value[range.upperBound..<value.index(before: value.endIndex)])
            return format("error.exit_status", text(prefix), detail)
        }
        if let separator = value.firstIndex(of: "：") {
            let prefix = String(value[..<separator])
            let detail = String(value[value.index(after: separator)...])
            let localizedPrefix = text(prefix)
            if localizedPrefix != prefix {
                return format("error.with_detail", localizedPrefix, detail)
            }
        }
        return localized
    }

    private static var preferredLanguage: String {
        selectedLanguageCode
            ?? Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "zh-Hans"
    }

    private static var localizationBundle: Bundle {
        guard let languageCode = selectedLanguageCode,
              let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    private static var selectedLanguageCode: String? {
        lock.lock()
        defer { lock.unlock() }
        return languageCode
    }

    private static func sourceValue(for key: String) -> String {
        switch key {
        case "deadline.expiration.days": return "%d 天后到期"
        case "deadline.expiration.hours": return "%d 小时后到期"
        case "deadline.expiration.imminent": return "即将到期"
        case "deadline.reset.days": return "%d 天后重置"
        case "deadline.reset.hours": return "%d 小时后重置"
        case "deadline.reset.imminent": return "即将重置"
        default: return key
        }
    }
}
