import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zh
    case ja
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .zh: "中文"
        case .ja: "日本語"
        case .en: "English"
        }
    }

    static func resolved(from rawValue: String) -> AppLanguage {
        let selected = AppLanguage(rawValue: rawValue) ?? .system
        guard selected == .system else { return selected }

        let languageCode = Locale.preferredLanguages.first?.lowercased() ?? ""
        if languageCode.hasPrefix("ja") { return .ja }
        if languageCode.hasPrefix("en") { return .en }
        return .zh
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .zh
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

func L(_ key: String, _ language: AppLanguage) -> String {
    LocalizationService.shared.localized(key, language: language)
}
