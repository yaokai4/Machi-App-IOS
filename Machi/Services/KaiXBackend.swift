import Foundation

/// KaiX backend configuration.
///
/// The Web client and the iOS App both target the same Python-based
/// unified backend (`web/server.py`). During development the backend
/// defaults to the deployed host. The base URL is overridable via
/// `Info.plist` (`KAIX_API_BASE`) or `UserDefaults` (`kaix.api.base`) so
/// QA / staging can be flipped without rebuilding.
enum KaiXBackend {
    /// Default base URL used when no override is set.
    static let defaultBaseURL = URL(string: "https://machicity.com")!

    // MARK: - Public-facing legal & support links
    //
    // These always point at the production marketing site, independent of
    // any `KAIX_API_BASE` override (a QA/staging API host has no published
    // /legal/privacy or /legal/terms page). Apple requires functional Privacy Policy +
    // Terms of Use links to be reachable in-app and on any auto-renewable
    // subscription screen (App Store Review Guideline 3.1.2 / 5.1.1).
    static let marketingSiteURL = URL(string: "https://machicity.com")!
    static let privacyPolicyURL = URL(string: "https://machicity.com/legal/privacy")!
    static let termsOfServiceURL = URL(string: "https://machicity.com/legal/terms")!
    static let commercialDisclosureURL = URL(string: "https://machicity.com/legal/commercial-disclosure")!
    /// Public support inbox (matches the web client's contact address).
    static let supportEmail = "hi@machicity.com"

    /// Effective base URL. The order of resolution is:
    /// 1. `UserDefaults` `kaix.api.base`
    /// 2. `Info.plist` `KAIX_API_BASE`
    /// 3. `defaultBaseURL`
    static var baseURL: URL {
        if let stored = UserDefaults.standard.string(forKey: "kaix.api.base"),
           let url = validatedBaseURL(stored) {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "KAIX_API_BASE") as? String,
           let url = validatedBaseURL(plist) {
            return url
        }
        return defaultBaseURL
    }

    /// Persist a new base URL override (call from settings).
    static func setBaseURL(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: "kaix.api.base")
        } else {
            UserDefaults.standard.removeObject(forKey: "kaix.api.base")
        }
    }

    private static func validatedBaseURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let host = url.host?.lowercased() else { return nil }
#if targetEnvironment(simulator)
        return url
#else
        let loopbackHosts = ["localhost", "127.0.0.1", "0.0.0.0", "::1"]
        guard !loopbackHosts.contains(host), !host.hasPrefix("127.") else {
            return nil
        }
        return url
#endif
    }

    /// Bearer token persisted in the iOS Keychain (with a one-time
    /// migration from the historical UserDefaults location — see
    /// `KaiXTokenStore.migrateLegacyIfNeeded`). The Web client uses
    /// `localStorage` under the same name so the concept stays
    /// symmetric across platforms; only the storage backend differs.
    static var token: String? {
        get { KaiXTokenStore.read() }
        set {
            if let value = newValue, !value.isEmpty {
                KaiXTokenStore.write(value)
            } else {
                KaiXTokenStore.delete()
            }
        }
    }
}
