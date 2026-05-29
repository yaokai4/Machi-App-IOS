import Foundation

/// KaiX backend configuration.
///
/// The Web client and the iOS App both target the same Python-based
/// unified backend (`web/server.py`). During development the backend
/// runs on localhost; in production this should point to the deployed
/// host. The base URL is overridable via `Info.plist` (`KAIX_API_BASE`)
/// or `UserDefaults` (`kaix.api.base`) so QA / staging can be flipped
/// without rebuilding.
enum KaiXBackend {
    /// Default base URL used when no override is set.
    static let defaultBaseURL = URL(string: "http://127.0.0.1:8787")!

    /// Effective base URL. The order of resolution is:
    /// 1. `UserDefaults` `kaix.api.base`
    /// 2. `Info.plist` `KAIX_API_BASE`
    /// 3. `defaultBaseURL`
    static var baseURL: URL {
        if let stored = UserDefaults.standard.string(forKey: "kaix.api.base"),
           let url = URL(string: stored) {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "KAIX_API_BASE") as? String,
           let url = URL(string: plist) {
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
