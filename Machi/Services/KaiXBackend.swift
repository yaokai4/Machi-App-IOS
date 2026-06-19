import Foundation

/// KaiX backend configuration.
///
/// The Web client and the iOS App both target the same Python-based
/// unified backend (`web/server.py`). During development the backend
/// defaults to the deployed host. The base URL is overridable via
/// `Info.plist` (`KAIX_API_BASE`) or, in debug builds only,
/// `UserDefaults` (`kaix.api.base`) so QA / staging can be flipped without
/// rebuilding while App Store builds stay pinned to a trusted production host.
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

    /// Marketing version straight from the bundle so Settings/About never
    /// drift from what's actually shipped to the App Store.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// "1.0 (42)" style display string for About screens.
    static var appVersionDisplay: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(appVersion) (\($0))" } ?? appVersion
    }

    /// Effective base URL. Release device builds deliberately ignore the
    /// mutable UserDefaults override so a production app cannot be redirected
    /// to an arbitrary API host by stale QA defaults or device tampering.
    static var baseURL: URL {
#if DEBUG
        if let stored = UserDefaults.standard.string(forKey: "kaix.api.base"),
           let url = validatedBaseURL(stored) {
            return url
        }
#endif
        if let plist = Bundle.main.object(forInfoDictionaryKey: "KAIX_API_BASE") as? String,
           let url = validatedBaseURL(plist) {
            return url
        }
        return defaultBaseURL
    }

    /// Persist a new base URL override (debug/QA only).
    static func setBaseURL(_ url: URL?) {
#if DEBUG
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: "kaix.api.base")
        } else {
            UserDefaults.standard.removeObject(forKey: "kaix.api.base")
        }
#else
        _ = url
        UserDefaults.standard.removeObject(forKey: "kaix.api.base")
#endif
    }

    private static func validatedBaseURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let host = url.host?.lowercased() else { return nil }
#if DEBUG || targetEnvironment(simulator)
        return url.scheme == "http" || url.scheme == "https" ? url : nil
#else
        guard url.scheme == "https" else { return nil }
        let loopbackHosts = ["localhost", "127.0.0.1", "0.0.0.0", "::1"]
        guard !loopbackHosts.contains(host), !host.hasPrefix("127.") else {
            return nil
        }
        let trustedHosts = ["machicity.com", "www.machicity.com", "api.machicity.com"]
        guard trustedHosts.contains(host) else { return nil }
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
