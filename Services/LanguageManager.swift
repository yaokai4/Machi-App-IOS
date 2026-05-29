import Foundation
import Combine

/// Holds the user's content-language preferences. App UI strings are
/// still driven by `AppLanguage` (the bundle / system); this store
/// only controls which posts the feeds prefer to surface.
///
/// **Persistence:** UserDefaults — survives relaunches, mirrors the
/// server-side `settings.content_language_preference` /
/// `settings.preferred_content_languages` once we wire the API in
/// Phase 3.
///
/// **Reactivity:** `@Published`. Feeds (HomeViewModel, CityChannel,
/// Discover, …) observe via `objectWillChange` and re-query on
/// change so a language switch refreshes every visible surface
/// without a manual pull-to-refresh.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    /// The user's single primary content-language choice. `.followApp`
    /// means "use whatever the UI language is right now"; `.multi`
    /// means "don't filter at all".
    @Published var preferred: ContentLanguage {
        didSet {
            guard preferred != oldValue else { return }
            UserDefaults.standard.set(preferred.rawValue, forKey: Keys.preferred)
        }
    }

    /// Additional languages the user is willing to see when there's
    /// not enough content in `preferred`. Order matters — earlier
    /// tags win when ranking.
    @Published var fallbacks: [ContentLanguage] {
        didSet {
            guard fallbacks != oldValue else { return }
            UserDefaults.standard.set(fallbacks.map(\.rawValue), forKey: Keys.fallbacks)
        }
    }

    private enum Keys {
        static let preferred = "kaix.contentLanguage.preferred"
        static let fallbacks = "kaix.contentLanguage.fallbacks"
    }

    private init() {
        let rawPreferred = UserDefaults.standard.string(forKey: Keys.preferred) ?? ContentLanguage.followApp.rawValue
        self.preferred = ContentLanguage(rawValue: rawPreferred) ?? .followApp

        let rawFallbacks = UserDefaults.standard.stringArray(forKey: Keys.fallbacks) ?? []
        self.fallbacks = rawFallbacks.compactMap { ContentLanguage(rawValue: $0) }
            .filter { $0 != .followApp && $0 != .multi }
    }

    /// Resolve the actual filter to apply, given the current UI
    /// language. `.followApp` becomes a concrete tag; `.multi`
    /// disables filtering (returns nil).
    func resolvedPrimary(for appLanguage: AppLanguage) -> ContentLanguage? {
        switch preferred {
        case .followApp:
            return .from(appLanguage: appLanguage)
        case .multi:
            return nil
        default:
            return preferred
        }
    }

    /// Ordered list of "languages we'd accept" — primary first, then
    /// the user's fallbacks, then a sensible default tail so a brand-new
    /// user with empty fallbacks still sees content. nil means "no
    /// filter at all" (returned only when preferred is `.multi`).
    func acceptableLanguages(for appLanguage: AppLanguage) -> [ContentLanguage]? {
        if preferred == .multi { return nil }
        var ordered: [ContentLanguage] = []
        if let primary = resolvedPrimary(for: appLanguage) {
            ordered.append(primary)
        }
        for fallback in fallbacks where !ordered.contains(fallback) {
            ordered.append(fallback)
        }
        // Default tail so newer users get content even if they haven't
        // configured fallbacks yet.
        for tail in [ContentLanguage.zh, .en, .ja] where !ordered.contains(tail) {
            ordered.append(tail)
        }
        return ordered
    }

    /// Wipe preferences (called from logout so the next account
    /// starts with a clean slate).
    func reset() {
        preferred = .followApp
        fallbacks = []
    }
}
