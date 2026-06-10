import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when the user taps a Machi system notification banner.
    /// userInfo: ["postId": String] when the notification targets a post.
    static let kaiXSystemNotificationTapped = Notification.Name("KaiXSystemNotificationTapped")
}

/// Bridges server-side social notifications (likes, comments, follows…)
/// into REAL iOS system notifications via `UNUserNotificationCenter`.
///
/// Remote APNs push needs server-side APNs infrastructure; until that
/// exists, this service makes every notification the app learns about
/// (foreground polling / sync) surface as a genuine system banner +
/// app-icon badge, and routes taps back into the app.
@MainActor
final class SystemNotificationService: NSObject {
    static let shared = SystemNotificationService()

    /// True while the in-app notifications list is frontmost, so we don't
    /// banner over the very list the user is reading.
    var suppressBanners = false

    private let center = UNUserNotificationCenter.current()
    private let deliveredKey = "machi.notifications.delivered.v1"
    private let deliveredCap = 400

    private override init() {
        super.init()
    }

    /// Install the delegate. Call once at app start — must happen before
    /// the first notification is delivered or tapped.
    func activate() {
        center.delegate = self
    }

    /// Ask for permission lazily AFTER login (App Review frowns on
    /// permission prompts at cold launch with no context).
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    /// Surface freshly-synced, unread server notifications as system
    /// banners. Each remote id is delivered at most once, persisted across
    /// launches, so re-syncs can never re-banner old items.
    func deliver(_ notifications: [NotificationEntity], actors: [String: UserEntity], language: AppLanguage) async {
        guard !notifications.isEmpty else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        var delivered = deliveredIds()
        var dirty = false
        for notification in notifications {
            let key = notification.remoteId ?? notification.id
            guard !delivered.contains(key) else { continue }
            delivered.append(key)
            dirty = true

            let content = UNMutableNotificationContent()
            let actorName = actors[notification.actorId]?.displayName
                ?? actors[notification.actorId]?.username
                ?? ""
            content.title = Self.bannerTitle(for: notification.type, actorName: actorName, language: language)
            let body = notification.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty, !Self.contentIsBoilerplate(body) {
                content.body = String(body.prefix(140))
            }
            content.sound = .default
            // Group banners per interaction type in the notification center.
            content.threadIdentifier = "machi.\(notification.typeRaw)"
            var info: [String: Any] = ["type": notification.typeRaw]
            if let postId = notification.targetPostId { info["postId"] = postId }
            content.userInfo = info

            let request = UNNotificationRequest(
                identifier: "machi.notif.\(key)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
        if dirty {
            saveDeliveredIds(delivered)
        }
    }

    /// Mirror the in-app unread count onto the home-screen app icon.
    func syncBadge(unreadCount: Int) {
        center.setBadgeCount(max(0, unreadCount)) { _ in }
    }

    /// Remove delivered banners once the user has read everything in-app.
    func clearDelivered() {
        center.removeAllDeliveredNotifications()
        syncBadge(unreadCount: 0)
    }

    // MARK: - delivered-id persistence (ordered, capped)

    private func deliveredIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: deliveredKey) ?? []
    }

    private func saveDeliveredIds(_ ids: [String]) {
        UserDefaults.standard.set(Array(ids.suffix(deliveredCap)), forKey: deliveredKey)
    }

    // MARK: - copy

    private static func bannerTitle(for type: NotificationType, actorName: String, language: AppLanguage) -> String {
        let action: String
        switch type {
        case .like:     action = L("notifLiked", language)
        case .repost:   action = L("notifReposted", language)
        case .comment:  action = L("notifCommented", language)
        case .reply:    action = L("notifReplied", language)
        case .mention:  action = L("notifMentioned", language)
        case .follow:   action = L("notifFollowed", language)
        case .bookmark: action = L("notifBookmarked", language)
        case .system:   return L("systemNotification", language)
        }
        guard !actorName.isEmpty else { return action }
        // JA strings begin with "が" and read as one clause after the
        // name; ZH/EN take a separating space.
        return language == .ja ? "\(actorName)\(action)" : "\(actorName) \(action)"
    }

    /// Server content for likes/follows repeats the action text ("喜欢了你
    /// 的帖子") — showing it again as the body under an identical title
    /// reads broken, so drop those.
    private static func contentIsBoilerplate(_ content: String) -> Bool {
        ["喜欢了你的帖子", "收藏了你的帖子", "转发了你的帖子", "关注了你"].contains(content)
    }
}

extension SystemNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let suppressed = await MainActor.run { self.suppressBanners }
        return suppressed ? [] : [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let postId = userInfo["postId"] as? String
        await MainActor.run {
            NotificationCenter.default.post(
                name: .kaiXSystemNotificationTapped,
                object: nil,
                userInfo: postId.map { ["postId": $0] }
            )
        }
    }
}
