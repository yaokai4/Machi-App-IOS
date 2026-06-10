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
