import Foundation

/// Language tag used to filter and rank the feed by user preference.
///
/// Distinct from `AppLanguage` (which only governs UI strings). A user
/// browsing in `.zh` UI may still prefer to see Japanese-language posts
/// because they live in Tokyo — KaiX treats these as orthogonal.
///
/// **Storage:** rawValues mirror the BCP-47 short tags used by the
/// server (`web/server.py:CONTENT_LANGUAGES`). `followApp` and `multi`
/// are app-only sentinels that the repository layer expands at query
/// time.
enum ContentLanguage: String, CaseIterable, Identifiable, Hashable {
    case followApp = "follow_app"   // 跟随 App 语言
    case zh
    case en
    case ja
    case ko
    case fr
    case es
    case multi = "multi"            // 多语言内容(不过滤)

    var id: String { rawValue }

    /// Server tag (the literal string written into `posts.language`).
    /// `followApp` / `multi` are app-only — they never round-trip to
    /// the server as-is and so return an empty string here.
    var serverTag: String {
        switch self {
        case .followApp, .multi: return ""
        case .zh, .en, .ja, .ko, .fr, .es: return rawValue
        }
    }

    /// User-facing title in the picker.
    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .followApp:
            return L("contentLanguageFollowApp", appLanguage)
        case .multi:
            return L("contentLanguageMulti", appLanguage)
        case .zh: return "中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .es: return "Español"
        }
    }

    /// Map from an `AppLanguage` to the closest content tag — used
    /// when the user picked `.followApp`.
    static func from(appLanguage: AppLanguage) -> ContentLanguage {
        switch appLanguage {
        case .zh: return .zh
        case .en: return .en
        case .ja: return .ja
        case .system: return .zh
        }
    }

    /// Parse a stored tag (DB / settings) back to an enum. Unknown
    /// values fall back to `.followApp` so legacy rows behave like
    /// "no explicit preference".
    static func from(serverTag: String) -> ContentLanguage {
        ContentLanguage(rawValue: serverTag) ?? .followApp
    }
}
