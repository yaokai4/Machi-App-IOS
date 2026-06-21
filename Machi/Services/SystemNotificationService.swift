import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when the user taps a Machi system notification banner.
    /// userInfo: ["postId": String] when the notification targets a post.
    static let kaiXSystemNotificationTapped = Notification.Name("KaiXSystemNotificationTapped")
    /// Posted whenever a server or local notification says a conversation has
    /// new activity. Active chat/inbox screens use this to refresh immediately
    /// instead of waiting for their next polling tick.
    static let kaiXConversationShouldRefresh = Notification.Name("KaiXConversationShouldRefresh")
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
    /// permission prompts at cold launch with no context). Whenever the
    /// permission is (or already was) granted, also (re)assert the APNs
    /// registration so killed-app pushes keep working across token
    /// rotations and reinstalls.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        await PushTokenService.refreshRegistration()
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
        var refreshConversationIds = Set<String>()
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
            if let conversationId = notification.targetConversationId { info["conversationId"] = conversationId }
            content.userInfo = info
            if let conversationId = info["conversationId"] as? String {
                refreshConversationIds.insert(conversationId)
            }

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
        refreshConversationIds.forEach(Self.postConversationRefresh)
    }

    /// Mirror the in-app unread count onto the home-screen app icon.
    func syncBadge(unreadCount: Int) {
        center.setBadgeCount(max(0, unreadCount)) { _ in }
    }

    /// Remove delivered banners once the user has read everything in-app.
    func clearDelivered() {
        center.removeAllDeliveredNotifications()
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
        case .message:  action = L("notifMessaged", language)
        case .listingInquiry: action = L("notifInquired", language)
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

    private static func postConversationRefresh(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        NotificationCenter.default.post(
            name: .kaiXConversationShouldRefresh,
            object: nil,
            userInfo: ["conversationId": conversationId]
        )
    }

    nonisolated private static func conversationId(from userInfo: [AnyHashable: Any]) -> String? {
        if let value = userInfo["conversationId"] as? String, !value.isEmpty { return value }
        if let value = userInfo["conversation_id"] as? String, !value.isEmpty { return value }
        return nil
    }
}

extension SystemNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let conversationId = Self.conversationId(from: notification.request.content.userInfo)
        let suppressed = await MainActor.run { self.suppressBanners }
        if let conversationId {
            await MainActor.run {
                Self.postConversationRefresh(conversationId)
            }
        }
        // willPresent only fires while the app is FOREGROUND. The user doesn't
        // want intrusive banners/sounds while actively using the app — keep the
        // entry in Notification Center + badge, but no banner or sound. On the
        // chat / messages / notifications screens, suppress entirely.
        return suppressed ? [] : [.list, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        var payload: [String: Any] = [:]
        if let postId = userInfo["postId"] as? String { payload["postId"] = postId }
        if let conversationId = userInfo["conversationId"] as? String { payload["conversationId"] = conversationId }
        if let conversationId = Self.conversationId(from: userInfo) {
            payload["conversationId"] = conversationId
            await MainActor.run {
                Self.postConversationRefresh(conversationId)
            }
        }
        let finalPayload = payload
        await MainActor.run {
            NotificationCenter.default.post(
                name: .kaiXSystemNotificationTapped,
                object: nil,
                userInfo: finalPayload.isEmpty ? nil : finalPayload
            )
        }
    }
}
