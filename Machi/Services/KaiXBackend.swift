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
    ///
    /// Debug launch arguments are intentionally stricter for loopback hosts:
    /// `-kaix.api.base http://127.0.0.1:8787` now requires `-KXAllowLocalAPI`.
    /// This keeps ordinary simulator smoke runs on production data instead of
    /// accidentally inheriting a stale local-backend argument and showing a
    /// first-screen "cannot connect" error.
    static var baseURL: URL {
#if DEBUG
        if let cli = launchArgumentValue("-kaix.api.base") {
            if let url = validatedBaseURL(cli), shouldUseCommandLineOverride(url) {
                return url
            }
        } else if let env = ProcessInfo.processInfo.environment["KAIX_API_BASE"] {
            // Test/CI host override (e.g. KaiXAPIClientTests). Loopback still
            // requires an explicit allow signal so a stray env var can't redirect
            // a real build — see shouldUseCommandLineOverride.
            if let url = validatedBaseURL(env), shouldUseCommandLineOverride(url) {
                return url
            }
        } else if let stored = UserDefaults.standard.string(forKey: "kaix.api.base"),
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

#if DEBUG
    private static func launchArgumentValue(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func shouldUseCommandLineOverride(_ url: URL) -> Bool {
        guard isLoopback(url) else { return true }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-KXAllowLocalAPI") { return true }
        // Explicit test/CI opt-in: the backend smoke tests set this, so a local
        // base URL from the environment is honoured without also needing the
        // launch argument.
        if ProcessInfo.processInfo.environment["KAIX_RUN_BACKEND_SMOKE_TESTS"] == "1" { return true }
        return UserDefaults.standard.bool(forKey: "kaix.api.allowLocal")
    }
#endif

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
        guard !isLoopback(url) else {
            return nil
        }
        let trustedHosts = ["machicity.com", "www.machicity.com", "api.machicity.com"]
        guard trustedHosts.contains(host) else { return nil }
        return url
#endif
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "0.0.0.0", "::1"].contains(host) || host.hasPrefix("127.")
    }

    /// Bearer token persisted in the iOS Keychain (with a one-time
    /// migration from the historical UserDefaults location — see
    /// `KaiXTokenStore.migrateLegacyIfNeeded`). The Web client uses
    /// `localStorage` under the same name so the concept stays
    /// symmetric across platforms; only the storage backend differs.
    static var token: String? {
        get {
            guard KaiXRuntimeFlags.allowBackendRequests else { return nil }
            return KaiXTokenStore.read()
        }
        set {
            guard KaiXRuntimeFlags.allowBackendRequests else { return }
            if let value = newValue, !value.isEmpty {
                KaiXTokenStore.write(value)
                // 新登录成功 → 允许下一次会话失效再触发一次退游客流程。
                sessionLock.lock(); sessionInvalidated = false; sessionLock.unlock()
            } else {
                KaiXTokenStore.delete()
            }
        }
    }

    private static let sessionLock = NSLock()
    private static var sessionInvalidated = false

    /// 为一次 401 原子地清 token,并返回【本调用是否是第一个】这么做的。
    /// N 个并发请求几乎同时拿到 401 时(会话过期/被撤销的"401 风暴"),只有第一个
    /// 返回 true 去触发退游客流程,其余返回 false 跳过——避免后台线程重复拆除
    /// 会话状态、叠加多个 toast。游客(token==nil)恒返回 false。
    static func invalidateSessionOnce() -> Bool {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard token != nil, !sessionInvalidated else { return false }
        sessionInvalidated = true
        token = nil   // 走 delete 分支,不重入 sessionLock
        return true
    }
}
