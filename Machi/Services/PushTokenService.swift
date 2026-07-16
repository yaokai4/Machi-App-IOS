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
    /// 登录态走登录版上传,游客走 C-3 游客端点 —— 两个 upload 各自以 bearer
    /// 有无为前置,同时调用恰好互斥。
    static func systemDidIssue(token deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: cacheKey)
        Task {
            await upload()
            await uploadForGuest()
        }
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

    /// P-4 游客召回(契约 C-3):游客通过软引导授予了通知权限。系统侧注册后,
    /// 缓存的 token 直接上传游客端点(POST /api/push/register-guest),归属到
    /// GuestSession.stableClientId;城市已知时带 city_slug,让该设备参与
    /// city_digest 城市召回。token 尚未回调落缓存时这里的上传是 no-op,
    /// `systemDidIssue` 拿到 token 会再补一次。首次真实登录后由
    /// `refreshRegistration()` 走登录版端点,服务端按 token 唯一重绑(防双发)。
    static func registerForGuest() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await uploadForGuest()
    }

    private static func upload() async {
        guard KaiXBackend.token != nil,
              let hex = UserDefaults.standard.string(forKey: cacheKey),
              !hex.isEmpty else { return }
        try? await KaiXAPIClient.shared.registerPushToken(hex)
    }

    /// C-3 游客上传:仅在无 bearer(真游客)且已有缓存 token 时打游客端点。
    private static func uploadForGuest() async {
        guard KaiXBackend.token == nil,
              let hex = UserDefaults.standard.string(forKey: cacheKey),
              !hex.isEmpty else { return }
        try? await KaiXAPIClient.shared.registerGuestPushToken(
            hex,
            stableClientId: GuestSession.stableClientId,
            citySlug: RegionStore.shared.current?.cityCode
        )
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
