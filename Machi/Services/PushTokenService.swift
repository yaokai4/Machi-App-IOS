import UIKit
import UserNotifications

/// Glue between Apple's remote-notification registration and the Machi
/// backend: caches the APNs device token the system hands us, uploads it
/// once a logged-in session exists, and unbinds it on logout so the next
/// account on a shared device never receives the previous account's pushes.
@MainActor
enum PushTokenService {
    private static let cacheKey = "machi.apns.token"

    /// AppDelegate callback path — system issued (or rotated) the token.
    static func systemDidIssue(token deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: cacheKey)
        Task { await upload() }
    }

    /// Ask the system for the token (answered from cache when already
    /// registered) and re-upload. Call after login and on cold start once
    /// notification permission is granted — token rotation across app
    /// reinstalls/OS updates is silent, so re-asserting is the only safe play.
    static func refreshRegistration() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await upload()
    }

    /// P-4 游客召回:游客通过软引导授予了通知权限。这里只做系统侧注册 ——
    /// APNs 签发的 device token 经 AppDelegate 回调落进本地缓存
    /// (`systemDidIssue`)。**不做**服务端上传:后端注册端点要求登录 bearer
    /// (web/server.py `api_register_push_token` → `require_user`),带着
    /// GuestSession.stableClientId 发也只会 401;缓存的 token 会在首次真实
    /// 登录后由 `refreshRegistration()`(ContentView 登录态 task 已调用)
    /// 自动补上传,游客期间授的权一分不浪费。
    static func registerForGuest() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
        // upload() intentionally not called: it already no-ops without a
        // bearer token, and there is no guest-capable endpoint yet.
    }

    private static func upload() async {
        guard KaiXBackend.token != nil,
              let hex = UserDefaults.standard.string(forKey: cacheKey),
              !hex.isEmpty else { return }
        try? await KaiXAPIClient.shared.registerPushToken(hex)
    }

    /// Best-effort unbind at logout. The endpoint needs no bearer (the
    /// token itself is the capability), so firing after the session is
    /// cleared is fine.
    static func unregisterForLogout() {
        guard let hex = UserDefaults.standard.string(forKey: cacheKey), !hex.isEmpty else { return }
        Task.detached {
            try? await KaiXAPIClient.shared.unregisterPushToken(hex)
        }
    }
}
