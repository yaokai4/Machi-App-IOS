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
    /// Posted after the user deletes an activity from its detail page.
    /// userInfo: ["id": String]. The events list removes that card immediately
    /// instead of leaving a dead card that 404s on tap (refreshSilently's
    /// pagination-preserve merge never drops rows that fell off page 1).
    static let kaiXEventRemoved = Notification.Name("KaiXEventRemoved")
    /// Posted after a room is disbanded (host) or left (member) from its detail
    /// page. userInfo: ["id": String]. The rooms list removes/refreshes it.
    static let kaiXRoomRemoved = Notification.Name("KaiXRoomRemoved")
    /// Posted after a post is deleted (from its detail page or the card menu).
    /// userInfo: ["ids": [String]] — the post plus any local reposts of it.
    /// Feed/city-channel lists drop those rows so a detail-page delete doesn't
    /// leave a tappable ghost card (the `?? post` fallback would otherwise keep
    /// rendering the in-memory entity that PostStore already forgot).
    static let kaiXPostRemoved = Notification.Name("KaiXPostRemoved")
}

/// Bridges server-side social notifications (likes, comments, follows…)
/// into REAL iOS system notifications via `UNUserNotificationCenter`.
///
/// Remote APNs push IS wired end-to-end (PushTokenService uploads the device
/// token; web/server_apns.py signs an ES256 provider JWT and pushes on DM /
/// inquiry / social events). This service complements it: it presents
/// foreground banners, owns the tap-routing delegate, and surfaces any
/// notification the in-app sync learns about as a genuine banner + app-icon
/// badge — so killed-app (APNs) and foreground (this) are both covered.
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

    /// P-4 游客召回:游客在软引导 sheet 上点了「开启提醒」。弹一次系统权限
    /// 弹窗(已决定过则跳过),授权成功就注册 APNs 把 device token 缓存好。
    /// 游客侧到此为止 —— 服务端 push-token 端点要求登录态(web/server.py
    /// api_register_push_token → require_user),token 的真正上传发生在首次
    /// 登录后的 refreshRegistration()。Returns whether permission ended up
    /// granted.
    @discardableResult
    func requestGuestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
        await PushTokenService.registerForGuest()
        return true
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
            // Carry the actor so tap-routing can open a follow/mention actor's
            // profile (ContentView.routeNotificationPayload), matching the
            // in-app NotificationsView.route(for:) behavior.
            if !notification.actorId.isEmpty { info["actorId"] = notification.actorId }
            if let postId = notification.targetPostId { info["postId"] = postId }
            if let listingId = notification.targetListingId { info["listingId"] = listingId }
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
        // Actor-less summary/system banners: return a standalone title so we
        // never render a dangling "<name> ..." with no name.
        case .savedSearch: return L("notifSavedSearch", language)
        case .favoritePriceDrop: return L("notifFavoritePriceDrop", language)
        case .favoriteClosed: return L("notifFavoriteClosed", language)
        case .followDigest: return L("notifFollowDigest", language)
        case .cityDigest: return L("notifCityDigest", language)
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
        if let type = userInfo["type"] as? String { payload["type"] = type }
        if let actorId = userInfo["actorId"] as? String { payload["actorId"] = actorId }
        if let postId = userInfo["postId"] as? String { payload["postId"] = postId }
        if let listingId = userInfo["listingId"] as? String { payload["listingId"] = listingId }
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
